import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bot/trading_bot.dart';
import '../models/bot_config.dart';

class BotState extends ChangeNotifier {
  static const _prefsKey = 'bot_config_v1';
  static const _secureTokenKey = 'bot_deriv_token';
  static const _legacyTokenKey = 'token';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  TradingBot? _bot;
  BotConfig config = const BotConfig(token: '');

  BotStatus status = BotStatus.idle;
  String currency = 'USD';
  bool accountIsVirtual = true;
  double balance = 0;
  double pnl = 0;
  int wins = 0;
  int losses = 0;
  int totalTrades = 0;
  double lastProbability = 0.5;
  String lastSignal = '-';
  final List<String> logs = [];

  bool get isRunning =>
      status == BotStatus.running ||
      status == BotStatus.connecting ||
      status == BotStatus.reconnecting;

  BotState() {
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    Map<String, dynamic> map = {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        map = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
    }

    // Migra o token do plaintext (SharedPreferences) para o Keystore.
    var token = await _secureStorage.read(key: _secureTokenKey);
    final legacyToken = map[_legacyTokenKey] as String?;
    if ((token == null || token.isEmpty) &&
        legacyToken != null &&
        legacyToken.isNotEmpty) {
      token = legacyToken;
      await _secureStorage.write(key: _secureTokenKey, value: token);
    }

    config = BotConfig(
      token: token ?? '',
      appId: map['appId'] as String? ?? '',
      symbol: map['symbol'] as String? ?? 'R_100',
      baseStake: (map['baseStake'] as num?)?.toDouble() ?? 1.0,
      durationTicks: map['durationTicks'] as int? ?? 5,
      entryThreshold: (map['entryThreshold'] as num?)?.toDouble() ?? 0.62,
      maxDailyLoss: (map['maxDailyLoss'] as num?)?.toDouble() ?? 25.0,
      takeProfit: (map['takeProfit'] as num?)?.toDouble() ?? 50.0,
      useMartingale: map['useMartingale'] as bool? ?? false,
      martingaleFactor: (map['martingaleFactor'] as num?)?.toDouble() ?? 2.0,
      martingaleMaxLevels: map['martingaleMaxLevels'] as int? ?? 3,
      maxTrades: map['maxTrades'] as int? ?? 100,
    );

    // Remove credenciais antigas do storage inseguro.
    if (map.containsKey(_legacyTokenKey)) {
      try {
        final cleaned = Map<String, dynamic>.from(map)..remove(_legacyTokenKey);
        await prefs.setString(_prefsKey, jsonEncode(cleaned));
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> saveConfig(BotConfig newConfig) async {
    config = newConfig;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode({
      'symbol': config.symbol,
      'baseStake': config.baseStake,
      'durationTicks': config.durationTicks,
      'entryThreshold': config.entryThreshold,
      'maxDailyLoss': config.maxDailyLoss,
      'takeProfit': config.takeProfit,
      'useMartingale': config.useMartingale,
      'martingaleFactor': config.martingaleFactor,
      'martingaleMaxLevels': config.martingaleMaxLevels,
      'maxTrades': config.maxTrades,
    }));
    try {
      await _secureStorage.write(key: _secureTokenKey, value: config.token);
    } catch (_) {}
    notifyListeners();
  }

  void log(String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    logs.add('[$ts] $message');
    if (logs.length > 300) logs.removeRange(0, logs.length - 300);
    notifyListeners();
  }

  String get missingCredentials {
    if (config.token.isEmpty) return 'Configure seu token PAT primeiro.';
    if (config.appId.isEmpty) {
      return 'Configure o App ID registrado em developers.deriv.com.';
    }
    return '';
  }

  void start() {
    if (isRunning) return;
    final missing = missingCredentials;
    if (missing.isNotEmpty) {
      log('AVISO: $missing');
      return;
    }
    status = BotStatus.connecting;
    totalTrades = 0;
    pnl = 0;
    wins = 0;
    losses = 0;
    lastProbability = 0.5;
    lastSignal = '-';
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
      onAccount: (a) {
        balance = a.balance;
        currency = a.currency;
        accountIsVirtual = a.isVirtual;
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
    status = BotStatus.connecting;
    _bot!.start().then((_) {
      if (_bot == null) return;
      if (!_bot!.api.isConnected && status != BotStatus.stopped) {
        status = BotStatus.error;
        notifyListeners();
      }
    });
  }

  void stop() {
    final bot = _bot;
    _bot = null;
    status = BotStatus.stopped;
    notifyListeners();
    bot?.stop('Parado pelo usuario', notify: false);
  }
}
