import 'dart:convert';
import 'dart:math' as math;

import 'indicators.dart';

class MLStrategy {
  static const List<int> _returnLags = [1, 2, 3, 5, 8, 13];

  /// Maior janela necessaria para calcular qualquer feature.
  static const int _maxWindow = 25;

  /// _returnLags.length + 3 (rsi, zscore, bollinger).
  static const int _featureCount = 9;

  final List<double> _weights = List.filled(_featureCount, 0.0);
  double _bias = 0;
  double _learningRate;

  int trainedSamples = 0;
  double lastRsi = 50;

  /// Alvo do treino: direcao do preco `targetHorizon` ticks a frente.
  /// Deve acompanhar a duracao do contrato negociado (durationTicks).
  int targetHorizon = 5;

  MLStrategy({double learningRate = 0.02})
      : _learningRate = learningRate,
        assert(
          _featureCount == _returnLags.length + 3,
          '_featureCount fora de sincronia com _returnLags',
        );

  /// Serializa o modelo para persistencia entre execucoes.
  Map<String, dynamic> toJson() => {
        'weights': _weights,
        'bias': _bias,
        'learningRate': _learningRate,
        'trainedSamples': trainedSamples,
        'targetHorizon': targetHorizon,
      };

  factory MLStrategy.fromJson(Map<String, dynamic> j) {
    final s = MLStrategy();
    final w = j['weights'];
    if (w is List && w.length == _featureCount) {
      for (var i = 0; i < _featureCount; i++) {
        s._weights[i] = (w[i] as num).toDouble();
      }
    }
    s._bias = (j['bias'] as num?)?.toDouble() ?? 0;
    s._learningRate = (j['learningRate'] as num?)?.toDouble() ?? 0.02;
    s.trainedSamples = (j['trainedSamples'] as num?)?.toInt() ?? 0;
    s.targetHorizon = (j['targetHorizon'] as num?)?.toInt() ?? 5;
    return s;
  }

  static MLStrategy? tryFromJson(String json) {
    if (json.trim().isEmpty) return null;
    try {
      return MLStrategy.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  List<double>? buildFeatures(List<double> closes) {
    if (closes.length < _maxWindow) return null;
    final features = <double>[];

    for (final lag in _returnLags) {
      final ret = closes.last / closes[closes.length - 1 - lag] - 1;
      // Escala x1000 e clampa para evitar updates explosivos no gradiente.
      features.add((ret * 10000 / 10).clamp(-20.0, 20.0));
    }

    final rsiVal = Indicators.rsiWilder(closes, 14);
    lastRsi = rsiVal ?? 50;
    features.add((lastRsi - 50) / 50);

    // z-score do ultimo retorno sobre a janela de 20 retornos.
    final returns = <double>[];
    for (var i = closes.length - 21; i < closes.length; i++) {
      returns.add(closes[i] / closes[i - 1] - 1);
    }
    features.add(Indicators.zScoreLast(returns, 20).clamp(-5.0, 5.0));

    final bb = Indicators.bollinger(closes, 20)!;
    final width = bb.upper - bb.lower;
    features.add(width == 0 ? 0 : ((closes.last - bb.lower) / width) * 2 - 1);

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
      // Decaimento L2 leve para evitar overfit em ruido.
      _weights[i] = _weights[i] * 0.9999 + _learningRate * error * features[i];
    }
    _bias += _learningRate * error;
    trainedSamples++;
    if (trainedSamples % 200 == 0) {
      _learningRate *= 0.9;
    }
  }

  /// Treino inicial sobre o historico, com o MESMO alvo do online:
  /// `closes[i + horizon] > closes[i]`.
  void warmUp(List<double> closes) {
    if (closes.length <= _maxWindow + 1) return;
    final horizon = targetHorizon < 1 ? 1 : targetHorizon;
    for (var i = _maxWindow; i < closes.length - horizon; i++) {
      final start = math.max(0, i + 1 - 3 * _maxWindow);
      final window = closes.sublist(start, i + 1);
      final f = buildFeatures(window);
      if (f != null) {
        train(f, closes[i + horizon] > closes[i]);
      }
    }
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