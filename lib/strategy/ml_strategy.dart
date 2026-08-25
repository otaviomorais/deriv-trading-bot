import 'dart:math' as math;

import 'indicators.dart';

class MLStrategy {
  static const List<int> _returnLags = [1, 2, 3, 5, 8, 13];

  /// Maior janela necessaria para calcular qualquer feature.
  static const int _maxWindow = 25;

  /// _returnLags.length + 3 (rsi, zscore, bollinger).
  /// (.length nao pode ser usado em expressao const)
  static const int _featureCount = 9;

  final List<double> _weights = List.filled(_featureCount, 0.0);
  double _bias = 0;
  double _learningRate;

  int trainedSamples = 0;
  double lastRsi = 50;

  MLStrategy({double learningRate = 0.02})
      : _learningRate = learningRate,
        assert(
          _featureCount == _returnLags.length + 3,
          '_featureCount fora de sincronia com _returnLags',
        );

  List<double>? buildFeatures(List<double> closes) {
    if (closes.length < _maxWindow) return null;
    final features = <double>[];

    for (final lag in _returnLags) {
      final ret = closes.last / closes[closes.length - 1 - lag] - 1;
      features.add(ret * 10000 / 10);
    }

    final rsiVal = Indicators.rsiWilder(closes, 14);
    lastRsi = rsiVal ?? 50;
    features.add((lastRsi - 50) / 50);

    // z-score do ultimo retorno sobre a janela de 20 retornos.
    final returns = <double>[];
    for (var i = closes.length - 21; i < closes.length; i++) {
      returns.add(closes[i] / closes[i - 1] - 1);
    }
    features.add(Indicators.zScoreLast(returns, 20));

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
      _weights[i] += _learningRate * error * features[i];
    }
    _bias += _learningRate * error;
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

  void reset() {
    for (var i = 0; i < _weights.length; i++) {
      _weights[i] = 0;
    }
    _bias = 0;
    trainedSamples = 0;
    _learningRate = 0.02;
  }
}
