import 'dart:math' as math;

class Indicators {
  /// RSI com suavizacao de Wilder (metodo classico).
  static double? rsiWilder(List<double> closes, int period) {
    if (closes.length <= period) return null;
    var avgGain = 0.0;
    var avgLoss = 0.0;
    for (var i = 1; i <= period; i++) {
      final diff = closes[i] - closes[i - 1];
      if (diff >= 0) {
        avgGain += diff;
      } else {
        avgLoss -= diff;
      }
    }
    avgGain /= period;
    avgLoss /= period;
    for (var i = period + 1; i < closes.length; i++) {
      final diff = closes[i] - closes[i - 1];
      final gain = diff > 0 ? diff : 0.0;
      final loss = diff < 0 ? -diff : 0.0;
      avgGain = (avgGain * (period - 1) + gain) / period;
      avgLoss = (avgLoss * (period - 1) + loss) / period;
    }
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
        window.fold<double>(0, (acc, v) => acc + (v - mean) * (v - mean)) /
            period;
    final sd = math.sqrt(variance);
    return (upper: mean + 2 * sd, lower: mean - 2 * sd, middle: mean);
  }

  static double zScoreLast(List<double> values, int period) {
    if (values.length < 2) return 0;
    final p = math.min(period, values.length);
    final window = values.sublist(values.length - p);
    final mean = window.reduce((a, b) => a + b) / p;
    final variance =
        window.fold<double>(0, (acc, v) => acc + (v - mean) * (v - mean)) / p;
    final sd = math.sqrt(variance);
    if (sd == 0) return 0;
    return (window.last - mean) / sd;
  }

  /// MACD (linha, sinal, histograma) usando EMA 12/26/9, em O(n).
  static ({double macdLine, double signalLine, double histogram}) macd(
    List<double> closes, {
    int fast = 12,
    int slow = 26,
    int signal = 9,
  }) {
    if (closes.length < slow + signal) {
      return (macdLine: 0, signalLine: 0, histogram: 0);
    }
    final fastK = 2 / (fast + 1);
    final slowK = 2 / (slow + 1);
    final signalK = 2 / (signal + 1);

    var fastEma = closes.first;
    var slowEma = closes.first;
    var signalEma = 0.0;
    var macdLine = 0.0;

    for (var i = 1; i < closes.length; i++) {
      fastEma = closes[i] * fastK + fastEma * (1 - fastK);
      slowEma = closes[i] * slowK + slowEma * (1 - slowK);
      if (i >= slow - 1) {
        macdLine = fastEma - slowEma;
        if (i == slow - 1) {
          signalEma = macdLine;
        } else {
          signalEma = macdLine * signalK + signalEma * (1 - signalK);
        }
      }
    }

    return (
      macdLine: macdLine,
      signalLine: signalEma,
      histogram: macdLine - signalEma,
    );
  }

  /// ATR (Average True Range) sobre a serie de fechamentos.
  /// Aproximacao sem high/low: usa |close[i] - close[i-1]| como "range".
  static double atr(List<double> closes, int period) {
    if (closes.length <= period) return 0;
    var sum = 0.0;
    for (var i = closes.length - period; i < closes.length; i++) {
      sum += (closes[i] - closes[i - 1]).abs();
    }
    return sum / period;
  }
}
