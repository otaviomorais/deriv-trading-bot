import 'package:flutter_test/flutter_test.dart';
import 'package:deriv_trading_bot/models/bot_config.dart';

void main() {
  group('BotConfig', () {
    test('defaults de seguranca', () {
      const cfg = BotConfig(token: 'x', symbol: 'R_100');
      expect(cfg.paperTrading, isFalse);
      expect(cfg.cooldownTicks, greaterThanOrEqualTo(0));
      expect(cfg.accountType, BotConfig.accountDemo);
    });

    test('toJson/fromJson roundtrip com novos campos', () {
      const cfg = BotConfig(
        token: 'pat_123',
        appId: 'abc123',
        symbol: 'R_50',
        accountType: BotConfig.accountReal,
        baseStake: 2.5,
        durationTicks: 7,
        entryThreshold: 0.6,
        maxDailyLoss: 10,
        takeProfit: 30,
        useMartingale: true,
        martingaleFactor: 2.0,
        martingaleMaxLevels: 4,
        maxTrades: 50,
        paperTrading: true,
        cooldownTicks: 5,
      );
      final restored = BotConfig.fromJson(cfg.toJson());
      expect(restored.paperTrading, isTrue);
      expect(restored.cooldownTicks, 5);
      expect(restored.accountType, BotConfig.accountReal);
      expect(restored.durationTicks, 7);
      expect(restored.baseStake, 2.5);
    });

    test('fromJson com json antigo usa defaults', () {
      final restored = BotConfig.fromJson({'token': 't', 'symbol': 'R_10'});
      expect(restored.paperTrading, isFalse);
      expect(restored.cooldownTicks, 3);
      expect(restored.maxTrades, 100);
    });
  });
}