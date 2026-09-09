import 'dart:math' as math;

import 'indicators.dart';

class MLStrategy {
  static const List<int> _returnLags = [1, 2, 3, 5, 8, 13];

  /// Maior janela necessaria para calcular qualquer feature.
  static const int _maxWindow = 34;

  /// Total de features:
  ///  - 6 retornos defasados
  ///  - RSI normalizado
  ///  - z-score de volatilidade
  ///  - posicao no Bollinger
  ///  - momentum (retorno de 20 periodos)
  ///  - MACD (linha) e MACD (sinal)
  ///  - ATR normalizado (volatilidade de amplitude)
  ///
  /// (6 + 7 = 13. Valor literal porque expressoes constantes nao aceitam
  /// acesso a `.length`.)
  static const int _featureCount = 13;

  final List<double> _weights = List.filled(_featureCount, 0.0);
  double _bias = 0;
  double _learningRate;

  /// Regularizacao L2 + clipping de gradiente para evitar overfitting
  /// (indices sinteticos sao ruidos; sem isso o modelo "memoriza" ticks).
  final double _lambda;
  final double _clip;

  int trainedSamples = 0;
  double lastRsi = 50;

  MLStrategy({double learningRate = 0.02, double lambda = 1e-4, double clip = 1.0})
      : _learningRate = learningRate,
        _lambda = lambda,
        _clip = clip,
        assert(
          _featureCount == _returnLags.length + 7,
          '_featureCount fora de sincronia',
        );

  List<double>? buildFeatures(List<double> closes) {
    if (closes.length < _maxWindow) return null;
    final features = <double>[];

    // 6 retornos defasados (normalizados para escala estavel).
    for (final lag in _returnLags) {
      final ret = closes.last / closes[closes.length - 1 - lag] - 1;
      features.add(ret * 1000);
    }

    // RSI Wilder normalizado para [-1, 1].
    final rsiVal = Indicators.rsiWilder(closes, 14);
    lastRsi = rsiVal ?? 50;
    features.add((lastRsi - 50) / 50);

    // z-score do ultimo retorno sobre a janela de 20 retornos.
    final returns = <double>[];
    for (var i = closes.length - 21; i < closes.length; i++) {
      returns.add(closes[i] / closes[i - 1] - 1);
    }
    features.add(Indicators.zScoreLast(returns, 20));

    // Posicao na banda de Bollinger, mapeada para [-1, 1].
    final bb = Indicators.bollinger(closes, 20)!;
    final width = bb.upper - bb.lower;
    features.add(width == 0 ? 0 : ((closes.last - bb.lower) / width) * 2 - 1);

    // Momentum: retorno dos ultimos 20 periodos.
    final momentum = closes.last / closes[closes.length - 21] - 1;
    features.add(momentum * 1000);

    // MACD (12, 26, 9) e sinal: normalizados pelo preco.
    final macd = Indicators.macd(closes, fast: 12, slow: 26, signal: 9);
    features.add((macd.macdLine / closes.last) * 1000);
    features.add((macd.signalLine / closes.last) * 1000);

    // ATR normalizado (amplitude media real sobre o preco).
    final atr = Indicators.atr(closes, 14);
    features.add(atr <= 0 ? 0 : (atr / closes.last) * 1000);

    return features;
  }

  double _sigmoid(double x) => 1 / (1 + math.exp(-x));

  double predictProbability(List<double> features) {
    var z = _bias;
    for (var i = 0; i < features.length && i < _weights.length; i++) {
      z += _weights[i] * features[i];
    }
    return _sigmoid(z);
  }

  void train(List<double> features, bool wentUp) {
    final target = wentUp ? 1.0 : 0.0;
    final p = predictProbability(features);
    final error = target - p;

    for (var i = 0; i < features.length && i < _weights.length; i++) {
      // Gradiente com regularizacao L2: -lambda * w impede pesos explodirem.
      final grad = error * features[i] - _lambda * _weights[i];
      final clamped = grad.clamp(-_clip, _clip).toDouble();
      _weights[i] += _learningRate * clamped;
    }
    _bias += _learningRate * error.clamp(-_clip, _clip).toDouble();
    trainedSamples++;
    if (trainedSamples % 200 == 0) {
      _learningRate *= 0.9;
    }
  }

  /// Treino inicial sobre o historico.
  ///
  /// Usa uma janela deslizante limitada em vez de copiar a lista inteira
  /// a cada passo (O(n * _maxWindow) em vez de O(n^2)).
  void warmUp(List<double> closes) {
    if (closes.length <= _maxWindow + 1) return;
    for (var i = _maxWindow; i < closes.length - 1; i++) {
      final start = math.max(0, i + 1 - 3 * _maxWindow);
      final window = closes.sublist(start, i + 1);
      final f = buildFeatures(window);
      if (f != null) {
        train(f, closes[i + 1] > closes[i]);
      }
    }
  }

  /// Serializa o estado do modelo para persistir entre reinicios.
  Map<String, dynamic> toJson() => {
        'weights': _weights,
        'bias': _bias,
        'trainedSamples': trainedSamples,
        'learningRate': _learningRate,
      };

  /// Restaura o estado do modelo (validando dimensoes).
  void fromJson(Map<String, dynamic> j) {
    final w = j['weights'];
    if (w is List && w.length == _featureCount) {
      for (var i = 0; i < _featureCount; i++) {
        final v = w[i];
        _weights[i] = v is num ? v.toDouble() : 0.0;
      }
    }
    final b = j['bias'];
    _bias = b is num ? b.toDouble() : 0.0;
    final s = j['trainedSamples'];
    trainedSamples = s is num ? s.toInt() : 0;
    final lr = j['learningRate'];
    _learningRate = lr is num ? lr.toDouble() : 0.02;
  }

  void reset() {
    for (var i = 0; i < _weights.length; i++) {
      _weights[i] = 0;
    }
    _bias = 0;
    trainedSamples = 0;
    _learningRate = 0.02;
  }
}
