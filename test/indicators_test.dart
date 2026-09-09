import 'package:flutter_test/flutter_test.dart';
import 'package:deriv_trading_bot/strategy/indicators.dart';

void main() {
  group('Indicators.rsiWilder', () {
    test('retorna null com dados insuficientes', () {
      expect(Indicators.rsiWilder(List.filled(10, 100.0), 14), isNull);
    });

    test('RSI = 100 quando so ha ganhos', () {
      final closes = List.generate(30, (i) => 100.0 + i);
      expect(Indicators.rsiWilder(closes, 14), 100);
    });

    test('RSI = 0 quando so ha perdas', () {
      final closes = List.generate(30, (i) => 200.0 - i);
      expect(Indicators.rsiWilder(closes, 14), 0);
    });

    test('RSI fica entre 0 e 100 em serie mista', () {
      final closes = <double>[
        for (var i = 0; i < 40; i++) 100 + (i % 5) * 2.0 - (i % 3)
      ];
      final rsi = Indicators.rsiWilder(closes, 14)!;
      expect(rsi, greaterThan(0));
      expect(rsi, lessThan(100));
    });
  });

  group('Indicators.bollinger', () {
    test('retorna null com dados insuficientes', () {
      expect(Indicators.bollinger([1, 2, 3], 20), isNull);
    });

    test('bandas simetricas em torno da media', () {
      final closes = List.filled(25, 50.0);
      final bb = Indicators.bollinger(closes, 20)!;
      expect(bb.middle, 50);
      expect(bb.upper, closeTo(50, 1e-9));
      expect(bb.lower, closeTo(50, 1e-9));
    });
  });

  group('Indicators.zScoreLast', () {
    test('z-score zero em serie constante', () {
      expect(Indicators.zScoreLast(List.filled(30, 7.0), 20), 0);
    });

    test('z-score positivo para ultimo valor acima da media', () {
      final closes = <double>[for (var i = 0; i < 19; i++) 100.0, 110.0];
      expect(Indicators.zScoreLast(closes, 20), greaterThan(0));
    });
  });

  group('Indicators.macd', () {
    test('retorna zeros com dados insuficientes', () {
      final m = Indicators.macd(List.filled(10, 100.0));
      expect(m.macdLine, 0);
      expect(m.signalLine, 0);
    });

    test('macd linha positiva em tendencia de alta', () {
      final closes = <double>[for (var i = 0; i < 60; i++) 100 + i * 0.5];
      final m = Indicators.macd(closes);
      expect(m.macdLine, greaterThan(0));
    });

    test('macd linha negativa em tendencia de baixa', () {
      final closes = <double>[for (var i = 0; i < 60; i++) 200 - i * 0.5];
      final m = Indicators.macd(closes);
      expect(m.macdLine, lessThan(0));
    });
  });

  group('Indicators.atr', () {
    test('retorna zero com dados insuficientes', () {
      expect(Indicators.atr(List.filled(5, 100.0), 14), 0);
    });

    test('atr positivo em serie variavel', () {
      final closes = <double>[for (var i = 0; i < 30; i++) 100 + (i % 3)];
      expect(Indicators.atr(closes, 14), greaterThan(0));
    });

    test('atr zero em serie constante', () {
      expect(Indicators.atr(List.filled(30, 50.0), 14), 0);
    });
  });
}
