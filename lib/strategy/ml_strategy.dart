import 'dart:math' as math;

import 'indicators.dart';

class MLStrategy {
  static const List<int> _returnLags = [1, 2, 3, 5, 8, 13];
  static const int _featureCount = 9;

  final List<double> _weights = List.filled(_featureCount, 0.0);
  double _bias = 0;
  double _learningRate;

  int trainedSamples = 0;
  double lastRsi = 50;

  MLStrategy({double learningRate = 0.02}) : _learningRate = learningRate;

  List<double>? buildFeatures(List<double> closes) {
    if (closes.length < 25) return null;
    final features = <double>[];

    for (final lag in _returnLags) {
      final ret = closes.last / closes[closes.length - 1 - lag] - 1;
      features.add(ret * 10000 / 10);
    }

    final rsiVal = Indicators.rsi(closes, 14);
    lastRsi = rsiVal ?? 50;
    features.add((lastRsi - 50) / 50);

    final returns = <double>[];
    for (var i = closes.length - 20; i < closes.length; i++) {
      returns.add(closes[i] / closes[i - 1] - 1);
    }
    final mean = returns.reduce((a, b) => a + b) / returns.length;
    final variance =
        returns.fold<double>(0, (acc, v) => acc + (v - mean) * (v - mean)) /
            returns.length;
    final sd = math.sqrt(variance);
    features.add(sd == 0 ? 0 : (returns.last - mean) / sd);

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

  void warmUp(List<double> closes) {
    for (var i = 25; i < closes.length - 1; i++) {
      final window = closes.sublist(0, i + 1);
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
