import 'dart:math' as math;

class Indicators {
  static double? ema(List<double> values, int period) {
    if (values.length < period) return null;
    final k = 2 / (period + 1);
    var e = values.sublist(0, period).reduce((a, b) => a + b) / period;
    for (var i = period; i < values.length; i++) {
      e = values[i] * k + e * (1 - k);
    }
    return e;
  }

  static double? rsi(List<double> closes, int period) {
    if (closes.length <= period) return null;
    var gain = 0.0;
    var loss = 0.0;
    for (var i = closes.length - period; i < closes.length; i++) {
      final diff = closes[i] - closes[i - 1];
      if (diff >= 0) {
        gain += diff;
      } else {
        loss -= diff;
      }
    }
    final avgGain = gain / period;
    final avgLoss = loss / period;
    if (avgLoss == 0) return 100;
    final rs = avgGain / avgLoss;
    return 100 - (100 / (1 + rs));
  }

  static ({double upper, double lower, double middle})? bollinger(
    List<double> closes,
    int period,
  ) {
    if (closes.length < period) return null;
    final window = closes.sublist(closes.length - period);
    final mean = window.reduce((a, b) => a + b) / period;
    final variance =
        window.fold<double>(0, (acc, v) => acc + (v - mean) * (v - mean)) / period;
    final sd = math.sqrt(variance);
    return (upper: mean + 2 * sd, lower: mean - 2 * sd, middle: mean);
  }

  static double? zScoreLast(List<double> values, int period) {
    if (values.length < period) return null;
    final window = values.sublist(values.length - period);
    final mean = window.reduce((a, b) => a + b) / period;
    final variance =
        window.fold<double>(0, (acc, v) => acc + (v - mean) * (v - mean)) / period;
    final sd = math.sqrt(variance);
    if (sd == 0) return 0;
    return (window.last - mean) / sd;
  }
}
