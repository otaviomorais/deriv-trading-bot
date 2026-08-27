import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/bot_config.dart';
import 'trading_bot.dart';

@pragma('vm:entry-point')
void startBotTaskCallback() {
  FlutterForegroundTask.setTaskHandler(BotTaskHandler());
}

class BotTaskHandler extends TaskHandler {
  TradingBot? _bot;

  void _send(Map<String, dynamic> data) {
    FlutterForegroundTask.sendDataToMain(data);
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _send({'t': 'status', 's': 'connecting'});
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map<String, dynamic>) return;
    final cmd = data['cmd'];
    if (cmd == 'start') {
      final config = BotConfig.fromJson(
        (data['config'] as Map).cast<String, dynamic>(),
      );
      _startBot(config);
    } else if (cmd == 'stop') {
      _stopBot('Parado pelo usuario');
      _send({'t': 'status', 's': 'stopped'});
    } else if (cmd == 'query') {
      _send({
        't': 'status',
        's': _bot != null && _bot!.api.isConnected ? 'running' : 'stopped',
      });
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _stopBot('Servico encerrado pelo sistema', notify: false);
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'btn_stop') {
      _stopBot('Parado pela notificacao');
      _send({'t': 'status', 's': 'stopped'});
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  void _startBot(BotConfig config) {
    if (_bot != null) {
      _send({'t': 'log', 'm': 'AVISO: bot ja esta em execucao.'});
      return;
    }
    _bot = TradingBot(
      config: config,
      onLog: (m) {
        // Logcat (capturável via `logcat -s flutter`) + arquivo no Download.
        try {
          File('/storage/emulated/0/Download/deriv_bot.log').writeAsStringSync(
              '${DateTime.now().toIso8601String().substring(11, 19)} $m\n',
              mode: FileMode.append,
              flush: true);
        } catch (_) {}
        debugPrint('[derivbot] $m');
        _send({'t': 'log', 'm': m});
      },
      onSignal: (p) => _send({'t': 'signal', 'p': p}),
      onAccount: (a) => _send({
        't': 'account',
        'bal': a.balance,
        'cur': a.currency,
        'virt': a.isVirtual,
      }),
      onTradeClosed: (r) => _send({
        't': 'trade',
        'profit': r.profit,
        'pnl': r.pnl,
        'wins': r.wins,
        'losses': r.losses,
      }),
      onStopped: (reason) {
        _updateNotification(reason);
        _send({'t': 'status', 's': 'stopped'});
      },
    );
    _bot!.start().then((_) {
      if (_bot != null && _bot!.api.isConnected) {
        _updateNotification(
            'Operando ${config.symbol} (${config.accountType.toUpperCase()})');
        _send({'t': 'status', 's': 'running'});
      }
    });
  }

  Future<void> _stopBot(String reason, {bool notify = true}) async {
    final bot = _bot;
    _bot = null;
    await bot?.stop(reason, notify: notify);
  }

  void _updateNotification(String text) {
    FlutterForegroundTask.updateService(
      notificationTitle: 'Deriv AI Bot',
      notificationText: text,
    );
  }
}

Map<String, dynamic> decodeTaskData(Object data) {
  if (data is Map<String, dynamic>) return data;
  if (data is String) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
  }
  return const {};
}
