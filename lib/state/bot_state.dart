import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bot/bot_task_handler.dart';
import '../bot/trading_bot.dart';
import '../models/bot_config.dart';

class BotState extends ChangeNotifier {
  static const _prefsKey = 'bot_config_v1';
  static const _secureTokenKey = 'bot_deriv_token';
  static const _modelKey = 'bot_model_v1';
  static const _dayKeyKey = 'bot_day_key';
  static const _dayPnlKey = 'bot_day_pnl';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  BotConfig config = const BotConfig(token: '', symbol: 'R_100');

  BotStatus status = BotStatus.idle;
  String currency = 'USD';
  bool accountIsVirtual = true;
  double balance = 0;
  double pnl = 0;
  double dailyPnl = 0;
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
    if (Platform.isAndroid) {
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
      _reattachIfServiceAlive();
    }
  }

  Future<void> _reattachIfServiceAlive() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        status = BotStatus.connecting;
        notifyListeners();
        FlutterForegroundTask.sendDataToTask({'cmd': 'query'});
      }
    } catch (_) {}
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

    var token = await _secureStorage.read(key: _secureTokenKey);
    final legacyToken = map['token'] as String?;
    if ((token == null || token.isEmpty) &&
        legacyToken != null &&
        legacyToken.isNotEmpty) {
      token = legacyToken;
      await _secureStorage.write(key: _secureTokenKey, value: token);
    }

    config = BotConfig(
      token: token ?? '',
      appId: map['appId'] as String? ?? '33wAcoYXHpsPdruTW0b7C',
      symbol: map['symbol'] as String? ?? 'R_100',
      accountType: (map['accountType'] as String?) == BotConfig.accountReal
          ? BotConfig.accountReal
          : BotConfig.accountDemo,
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

    if (map.containsKey('token')) {
      try {
        final cleaned = Map<String, dynamic>.from(map)..remove('token');
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
      'accountType': config.accountType,
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

  static final File _persistLog = File('/storage/emulated/0/Download/deriv_bot.log');

  void log(String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    logs.add('[$ts] $message');
    if (logs.length > 300) logs.removeRange(0, logs.length - 300);
    // Persiste para diagnostico externo (via Termux/adb) e para logcat.
    try {
      _persistLog.writeAsStringSync('[$ts] $message\n',
          mode: FileMode.append, flush: true);
    } catch (_) {}
    notifyListeners();
  }

  String get missingCredentials {
    if (config.token.isEmpty) return 'Configure seu token PAT primeiro.';
    if (config.appId.isEmpty) {
      return 'Configure o App ID registrado em developers.deriv.com.';
    }
    return '';
  }

  // ------------------------------------------------------------------
  // Controle do servico em segundo plano (Android)
  // ------------------------------------------------------------------

  void _initService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'deriv_bot_service',
        channelName: 'Deriv AI Bot',
        channelDescription:
            'Mantem o bot conectado a Deriv em segundo plano.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _requestPermissions() async {
    if (!Platform.isAndroid) return;
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  Future<void> start() async {
    if (isRunning) return;
    final missing = missingCredentials;
    if (missing.isNotEmpty) {
      log('AVISO: $missing');
      return;
    }

    if (!Platform.isAndroid) {
      log('AVISO: modo persistente disponivel apenas no Android.');
      return;
    }

    totalTrades = 0;
    pnl = 0;
    dailyPnl = 0;
    wins = 0;
    losses = 0;
    lastProbability = 0.5;
    lastSignal = '-';
    status = BotStatus.connecting;
    notifyListeners();

    await _requestPermissions();
    _initService();

    final result = await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Deriv AI Bot',
      notificationText: 'Conectando a Deriv...',
      notificationButtons: const [
        NotificationButton(id: 'btn_stop', text: 'PARAR'),
      ],
      callback: startBotTaskCallback,
    );

    switch (result) {
      case ServiceRequestSuccess():
        log('Servico em segundo plano iniciado.');
        String? modelJson;
        String? dayKey;
        var dayPnl = 0.0;
        try {
          final prefs = await SharedPreferences.getInstance();
          modelJson = prefs.getString(_modelKey);
          dayKey = prefs.getString(_dayKeyKey);
          dayPnl = prefs.getDouble(_dayPnlKey) ?? 0;
        } catch (_) {}
        FlutterForegroundTask.sendDataToTask({
          'cmd': 'start',
          'config': config.toJson(),
          if (modelJson != null && modelJson.isNotEmpty) 'model': modelJson,
          if (dayKey != null) 'dayKey': dayKey,
          'dayPnl': dayPnl,
        });
      case ServiceRequestFailure(error: final e):
        status = BotStatus.error;
        log('ERRO: nao foi possivel iniciar o servico ($e)');
        notifyListeners();
    }
  }

  Future<void> stop() async {
    status = BotStatus.stopped;
    notifyListeners();
    if (!Platform.isAndroid) return;
    try {
      FlutterForegroundTask.sendDataToTask({'cmd': 'stop'});
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Mensagens vindas do isolate do servico
  // ------------------------------------------------------------------

  Future<void> _onTaskData(Object data) async {
    final msg = decodeTaskData(data);
    switch (msg['t']) {
      case 'log':
        final m = msg['m'];
        if (m is String && m.isNotEmpty) log(m);
        break;
      case 'signal':
        final p = (msg['p'] as num?)?.toDouble() ?? lastProbability;
        lastProbability = p;
        final dir = p >= 0.5 ? 'ALTA' : 'BAIXA';
        lastSignal = '$dir (${(p * 100).toStringAsFixed(1)}%)';
        break;
      case 'account':
        balance = (msg['bal'] as num?)?.toDouble() ?? balance;
        currency = msg['cur'] as String? ?? currency;
        accountIsVirtual = msg['virt'] as bool? ?? accountIsVirtual;
        break;
      case 'trade':
        pnl = (msg['pnl'] as num?)?.toDouble() ?? pnl;
        dailyPnl = (msg['dPnl'] as num?)?.toDouble() ?? dailyPnl;
        wins = (msg['wins'] as num?)?.toInt() ?? wins;
        losses = (msg['losses'] as num?)?.toInt() ?? losses;
        totalTrades++;
        break;
      case 'model':
        final j = msg['j'];
        if (j is String && j.isNotEmpty) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_modelKey, j);
          } catch (_) {}
        }
        break;
      case 'day':
        final k = msg['k'];
        final p = (msg['p'] as num?)?.toDouble();
        if (k is String && p != null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(_dayKeyKey, k);
            await prefs.setDouble(_dayPnlKey, p);
          } catch (_) {}
        }
        break;
      case 'status':
        final s = msg['s'];
        if (s == 'running') {
          status = BotStatus.running;
        } else if (s == 'connecting') {
          status = BotStatus.connecting;
        } else if (s == 'stopped') {
          status = BotStatus.stopped;
        }
        break;
    }
    notifyListeners();
  }
}
