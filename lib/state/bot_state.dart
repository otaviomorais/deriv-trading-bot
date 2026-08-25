import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bot/trading_bot.dart';
import '../models/bot_config.dart';

class BotState extends ChangeNotifier {
  static const _prefsKey = 'bot_config_v1';

  TradingBot? _bot;
  BotConfig config = const BotConfig(token: '');

  BotStatus status = BotStatus.idle;
  double balance = 0;
  double pnl = 0;
  int wins = 0;
  int losses = 0;
  int totalTrades = 0;
  double lastProbability = 0.5;
  String lastSignal = '-';
  final List<String> logs = [];

  bool get isRunning => status == BotStatus.running || status == BotStatus.connecting;

  BotState() {
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        config = BotConfig(
          token: map['token'] as String? ?? '',
          symbol: map['symbol'] as String? ?? 'R_100',
          baseStake: (map['baseStake'] as num?)?.toDouble() ?? 1.0,
          durationTicks: map['durationTicks'] as int? ?? 5,
          entryThreshold: (map['entryThreshold'] as num?)?.toDouble() ?? 0.62,
          maxDailyLoss: (map['maxDailyLoss'] as num?)?.toDouble() ?? 25.0,
          takeProfit: (map['takeProfit'] as num?)?.toDouble() ?? 50.0,
          useMartingale: map['useMartingale'] as bool? ?? false,
          martingaleFactor: (map['martingaleFactor'] as num?)?.toDouble() ?? 2.0,
          maxTrades: map['maxTrades'] as int? ?? 100,
        );
        notifyListeners();
      } catch (_) {}
    }
  }

  Future<void> saveConfig(BotConfig newConfig) async {
    config = newConfig;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode({
      'token': config.token,
      'symbol': config.symbol,
      'baseStake': config.baseStake,
      'durationTicks': config.durationTicks,
      'entryThreshold': config.entryThreshold,
      'maxDailyLoss': config.maxDailyLoss,
      'takeProfit': config.takeProfit,
      'useMartingale': config.useMartingale,
      'martingaleFactor': config.martingaleFactor,
      'maxTrades': config.maxTrades,
    }));
    notifyListeners();
  }

  void log(String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    logs.add('[$ts] $message');
    if (logs.length > 300) logs.removeRange(0, logs.length - 300);
    notifyListeners();
  }

  void start() {
    if (isRunning || config.token.isEmpty) return;
    status = BotStatus.connecting;
    totalTrades = 0;
    pnl = 0;
    wins = 0;
    losses = 0;
    notifyListeners();

    _bot = TradingBot(
      config: config,
      onLog: log,
      onSignal: (p) {
        lastProbability = p;
        final dir = p >= 0.5 ? 'ALTA' : 'BAIXA';
        lastSignal = '$dir (${(p * 100).toStringAsFixed(1)}%)';
        notifyListeners();
      },
      onBalance: (b) {
        balance = b;
        notifyListeners();
      },
      onTradeClosed: (r) {
        pnl = r.pnl;
        wins = r.wins;
        losses = r.losses;
        notifyListeners();
      },
      onStopped: (_) {
        status = BotStatus.stopped;
        notifyListeners();
      },
    );
    _bot!.start().then((_) {
      if (_bot != null && !_bot!.api.isConnected) return;
      status = BotStatus.running;
      notifyListeners();
    });
  }

  void stop() {
    _bot?.stop('Parado pelo usuario');
    _bot = null;
    status = BotStatus.stopped;
    notifyListeners();
  }
}
