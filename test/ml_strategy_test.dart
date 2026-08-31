import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:deriv_trading_bot/strategy/ml_strategy.dart';

void main() {
  group('MLStrategy', () {
    test('buildFeatures retorna null com poucos dados', () {
      final s = MLStrategy();
      expect(s.buildFeatures([1, 2, 3]), isNull);
    });

    test('buildFeatures retorna o numero correto de features', () {
      final s = MLStrategy();
      final closes = <double>[for (var i = 0; i < 50; i++) 100 + i * 0.1];
      final f = s.buildFeatures(closes)!;
      expect(f.length, 9); // 6 lags + rsi + zscore + bollinger
    });

    test('predictProbability sempre retorna valor entre 0 e 1', () {
      final s = MLStrategy();
      final closes = <double>[for (var i = 0; i < 50; i++) 100 + i * 0.1];
      final f = s.buildFeatures(closes)!;
      final p = s.predictProbability(f);
      expect(p, greaterThanOrEqualTo(0));
      expect(p, lessThanOrEqualTo(1));
    });

    test('treino move a probabilidade na direcao do alvo', () {
      final s = MLStrategy();
      final closes = <double>[for (var i = 0; i < 50; i++) 100 + i * 0.1];
      final f = s.buildFeatures(closes)!;
      final before = s.predictProbability(f);
      for (var i = 0; i < 50; i++) {
        s.train(f, true);
      }
      final after = s.predictProbability(f);
      expect(after, greaterThan(before));
    });

    test('warmUp treina sem erro e conta amostras (historico curto)', () {
      final s = MLStrategy();
      final closes = <double>[
        for (var i = 0; i < 120; i++) 100 + math.sin(i / 5) * 2
      ];
      s.warmUp(closes);
      expect(s.trainedSamples, greaterThan(0));
      expect(s.trainedSamples, lessThan(closes.length));
    });

    test('reset volta ao estado inicial', () {
      final s = MLStrategy();
      final closes = <double>[for (var i = 0; i < 60; i++) 100 + i * 0.2];
      final f = s.buildFeatures(closes)!;
      s.train(f, true);
      s.reset();
      expect(s.trainedSamples, 0);
      expect(s.predictProbability(f), 0.5);
    });

    test('toJson/fromJson preserva pesos e previsoes', () {
      final s = MLStrategy();
      final closes = <double>[for (var i = 0; i < 60; i++) 100 + i * 0.2];
      final f = s.buildFeatures(closes)!;
      for (var i = 0; i < 30; i++) {
        s.train(f, i.isEven);
      }
      final before = s.predictProbability(f);
      final restored = MLStrategy.fromJson(s.toJson());
      expect(restored.trainedSamples, s.trainedSamples);
      expect(restored.predictProbability(f), closeTo(before, 1e-9));
    });

    test('tryFromJson ignora conteudo invalido', () {
      expect(MLStrategy.tryFromJson(''), isNull);
      expect(MLStrategy.tryFromJson('nao-json'), isNull);
      expect(MLStrategy.tryFromJson('{"bias": "x"}'), isNull);
      expect(MLStrategy.tryFromJson('{"bias": 1}'), isNotNull);
    });

    test('warmUp respeita o alvo de N ticks', () {
      final s = MLStrategy()..targetHorizon = 5;
      final closes = <double>[
        for (var i = 0; i < 120; i++) 100 + math.sin(i / 5) * 2
      ];
      s.warmUp(closes);
      expect(s.trainedSamples, greaterThan(0));
      // Com horizonte 5, sao treinadas as amostras i em [_maxWindow, len-1-h].
      expect(s.trainedSamples, lessThanOrEqualTo(120 - 5 - 25 + 1));
    });
  });
}
