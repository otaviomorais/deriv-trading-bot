import 'dart:async';
import 'dart:math' as math;

import '../models/bot_config.dart';
import '../services/deriv_api.dart';
import '../strategy/ml_strategy.dart';

enum BotStatus { idle, connecting, running, stopped, error }

class TradingBot {
  final MLStrategy strategy = MLStrategy();

  DerivApi get api => _api ??= DerivApi(appId: config.appId);
  DerivApi? _api;

  BotConfig config;
  final void Function(String message) onLog;
  final void Function(double probability) onSignal;
  final void Function(double balance) onBalance;
  final void Function(BotTradeResult result) onTradeClosed;
  final void Function(String reason) onStopped;

  final List<double> _closes = [];
  StreamSubscription<Map<String, dynamic>>? _tickSub;
  bool _inTrade = false;

  double currentStake = 1.0;
  double pnl = 0;
  int wins = 0;
  int losses = 0;
  int totalTrades = 0;
  int _consecutiveLosses = 0;
  bool _stopping = false;

  TradingBot({
    required this.config,
    required this.onLog,
    required this.onSignal,
    required this.onBalance,
    required this.onTradeClosed,
    required this.onStopped,
  }) {
    currentStake = config.baseStake;
  }

  Future<void> start() async {
    try {
      onLog('Conectando a Deriv...');
      await api.connect();
      final auth = await api.authorize(config.token);
      onLog('Autorizado: ${auth['fullname'] ?? auth['loginid'] ?? 'conta'}');

      final balance = await api.fetchBalance('USD');
      onBalance(balance);
      onLog('Saldo: \$${balance.toStringAsFixed(2)}');

      onLog('Carregando historico de ${config.symbol}...');
      _closes.clear();
      _closes.addAll(await api.fetchTicksHistory(config.symbol, count: 1000));
      onLog('Treinando modelo com ${_closes.length} ticks...');
      strategy.warmUp(_closes);
      onLog('Modelo pronto (${strategy.trainedSamples} amostras treinadas).');

      _tickSub = api
          .subscribe({
            'ticks_history': config.symbol,
            'count': 1,
            'end': 'latest',
            'style': 'ticks',
            'subscribe': 1,
          })
          .listen(_onTick, onError: (Object e) {
        onLog('Erro no stream de ticks: $e');
        stop('Erro no stream');
      });

      onLog('Bot iniciado em ${config.symbol}. Aguardando sinais...');
    } catch (e) {
      onLog('ERRO: $e');
      stop('Falha na inicializacao');
    }
  }

  void _onTick(Map<String, dynamic> msg) {
    if (_stopping) return;
    final tick = msg['tick'] as Map<String, dynamic>;
    final quote = (tick['quote'] as num).toDouble();

    if (_closes.isNotEmpty) {
      final prevFeatures = strategy.buildFeatures(_closes);
      if (prevFeatures != null) {
        strategy.train(prevFeatures, quote > _closes.last);
      }
    }
    _closes.add(quote);
    if (_closes.length > 2000) {
      _closes.removeRange(0, _closes.length - 1500);
    }

    final features = strategy.buildFeatures(_closes);
    if (features == null) return;
    final probUp = strategy.predictProbability(features);
    onSignal(probUp);

    if (_inTrade || totalTrades >= config.maxTrades) return;

    if (probUp >= config.entryThreshold) {
      _openTrade('CALL', probUp);
    } else if (probUp <= 1 - config.entryThreshold) {
      _openTrade('PUT', probUp);
    }
  }

  Future<void> _openTrade(String contractType, double prob) async {
    _inTrade = true;
    totalTrades++;
    onLog(
        'SINAL ${(prob * 100).toStringAsFixed(1)}% -> $contractType | Stake: \$${currentStake.toStringAsFixed(2)}');
    try {
      final contractId = await api.buyContract(
        contractType: contractType,
        stake: currentStake,
        duration: config.durationTicks,
        symbol: config.symbol,
      );
      onLog('Contrato #$contractId aberto.');

      api.subscribeContract(contractId).listen((msg) {
        final c = msg['proposal_open_contract'] as Map<String, dynamic>;
        if (c['is_sold'] == 1) {
          final profit = (c['profit'] as num).toDouble();
          _closeTrade(profit);
        }
      }, onError: (Object e) {
        onLog('Erro ao acompanhar contrato: $e');
        _inTrade = false;
      });
    } catch (e) {
      onLog('ERRO ao comprar contrato: $e');
      _inTrade = false;
    }
  }

  void _closeTrade(double profit) {
    pnl += profit;
    if (profit >= 0) {
      wins++;
      _consecutiveLosses = 0;
      currentStake = config.baseStake;
      onLog('WIN +\$${profit.toStringAsFixed(2)} | PnL: \$${pnl.toStringAsFixed(2)}');
    } else {
      losses++;
      _consecutiveLosses++;
      currentStake =
          config.useMartingale ? currentStake * config.martingaleFactor : config.baseStake;
      onLog('LOSS \$${profit.toStringAsFixed(2)} | PnL: \$${pnl.toStringAsFixed(2)}');
    }
    onTradeClosed(BotTradeResult(profit: profit, pnl: pnl, wins: wins, losses: losses));

    if (pnl <= -config.maxDailyLoss.abs()) {
      stop('STOP LOSS diario atingido (\$${pnl.toStringAsFixed(2)})');
    } else if (pnl >= config.takeProfit) {
      stop('TAKE PROFIT atingido (\$${pnl.toStringAsFixed(2)})');
    } else if (_consecutiveLosses >= 5) {
      stop('5 perdas consecutivas. Bot pausado por seguranca.');
    } else if (totalTrades >= config.maxTrades) {
      stop('Limite de operacoes ($totalTrades/${config.maxTrades}) atingido.');
    }
    _inTrade = false;
  }

  void stop(String reason) {
    if (_stopping) return;
    _stopping = true;
    _tickSub?.cancel();
    api.dispose();
    onLog('Bot parado: $reason');
    onStopped(reason);
  }

  static double confidenceLabel(double prob) => math.max(prob, 1 - prob);
}

class BotTradeResult {
  final double profit;
  final double pnl;
  final int wins;
  final int losses;
  BotTradeResult({
    required this.profit,
    required this.pnl,
    required this.wins,
    required this.losses,
  });
}
