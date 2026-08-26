import 'dart:async';

import '../models/bot_config.dart';
import '../services/deriv_api.dart';
import '../strategy/ml_strategy.dart';

enum BotStatus { idle, connecting, running, reconnecting, stopped, error }

class TradingBot {
  final DerivApi api;
  final MLStrategy strategy;

  BotConfig config;
  final void Function(String message) onLog;
  final void Function(double probability) onSignal;
  final void Function(AccountInfo account) onAccount;
  final void Function(BotTradeResult result) onTradeClosed;
  final void Function(String reason) onStopped;

  static const int _maxReconnectAttempts = 5;

  final List<double> _closes = [];
  StreamSubscription<Map<String, dynamic>>? _tickSub;
  StreamSubscription<Map<String, dynamic>>? _contractSub;
  StreamSubscription<Map<String, dynamic>>? _recoverySub;
  Timer? _contractWatchdog;
  Timer? _reconnectTimer;
  bool _inTrade = false;
  bool _disposed = false;

  String currency = 'USD';

  double currentStake = 1.0;
  double pnl = 0;
  int wins = 0;
  int losses = 0;
  int totalTrades = 0;
  int _consecutiveLosses = 0;
  int _martingaleLevel = 0;
  bool _stopping = false;
  int _reconnectAttempts = 0;
  int? _openContractId;

  TradingBot({
    required this.config,
    DerivApi? api,
    MLStrategy? strategy,
    required this.onLog,
    required this.onSignal,
    required this.onAccount,
    required this.onTradeClosed,
    required this.onStopped,
  })  : api = api ?? DerivApi(),
        strategy = strategy ?? MLStrategy() {
    currentStake = config.baseStake;
    this.api.onDisconnected = (reason) => _scheduleReconnect(reason);
  }

  Future<void> start() async {
    try {
      onLog('Autenticando na Deriv (nova API)...');
      await api.connect(
          token: config.token,
          appId: config.appId,
          accountType: config.accountType);

      final account = await api.fetchAccount();
      currency = account.currency;
      onAccount(account);
      onLog(
        'Conectado: ${account.isVirtual ? "DEMO" : "REAL"} ${account.accountId} '
        '| Saldo: ${account.balance.toStringAsFixed(2)} ${account.currency}',
      );

      await _recoverOpenContracts();

      onLog('Carregando historico de ${config.symbol}...');
      _closes.clear();
      _closes.addAll(await api.fetchTicksHistory(config.symbol, count: 1000));
      if (!_wasWarm) {
        onLog('Treinando modelo com ${_closes.length} ticks...');
        strategy.warmUp(_closes);
        _wasWarm = true;
        onLog('Modelo pronto (${strategy.trainedSamples} amostras).');
      } else {
        onLog('Modelo preservado (${strategy.trainedSamples} amostras).');
      }

      await _subscribeTicks();

      _reconnectAttempts = 0;
      onLog('Bot iniciado em ${config.symbol}. Aguardando sinais...');
    } catch (e) {
      onLog('ERRO: $e');
      stop('Falha na inicializacao: $e', notify: true);
    }
  }

  bool _wasWarm = false;

  Future<void> _recoverOpenContracts() async {
    try {
      _recoverySub?.cancel();
      _recoverySub = api.subscribeOpenContracts().listen((msg) {
        final c = msg['proposal_open_contract'] as Map<String, dynamic>?;
        if (c == null || c['is_sold'] == 1) return;
        final id = c['contract_id'] as int?;
        if (id == null) return;
        onLog('Contrato aberto recuperado #$id. Acompanhando ate o fim.');
        _adoptContract(id);
      });
      // Dá tempo para o servidor responder com posicoes abertas.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      _recoverySub?.cancel();
      _recoverySub = null;
    } catch (_) {
      // Sem posicoes abertas ou endpoint indisponivel; segue o fluxo.
    }
  }

  Future<void> _subscribeTicks() async {
    await _tickSub?.cancel();
    _tickSub = api.subscribeTicks(config.symbol).listen(
          _onTick,
          onError: (Object e) => _scheduleReconnect('Erro no stream de ticks: $e'),
        );
  }

  void _onTick(Map<String, dynamic> msg) {
    if (_stopping || _disposed) return;
    final tick = msg['tick'] as Map<String, dynamic>?;
    if (tick == null) return;
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
      'SINAL ${(prob * 100).toStringAsFixed(1)}% -> $contractType '
      '| Stake: ${currentStake.toStringAsFixed(2)} $currency',
    );
    try {
      final contractId = await api.buyContract(
        contractType: contractType,
        stake: currentStake,
        duration: config.durationTicks,
        symbol: config.symbol,
        currency: currency,
      );
      onLog('Contrato #$contractId aberto.');
      _adoptContract(contractId);
    } catch (e) {
      onLog('ERRO ao comprar contrato: $e');
      _inTrade = false;
      if (totalTrades > 0) totalTrades--;
    }
  }

  /// Acompanha um contrato (novo ou recuperado) ate a venda/expiracao.
  void _adoptContract(int contractId) {
    _inTrade = true;
    _openContractId = contractId;
    _contractSub?.cancel();
    _contractSub = api.subscribeContract(contractId).listen(
      (msg) {
        final c = msg['proposal_open_contract'] as Map<String, dynamic>?;
        if (c == null) return;
        if (c['is_sold'] == 1) {
          final profit = (c['profit'] as num?)?.toDouble() ?? 0;
          _closeTrade(profit);
        }
      },
      onError: (Object e) {
        onLog('Erro ao acompanhar contrato: $e');
        // Nao reseta _inTrade: o watchdog/recuperacao resolve.
      },
    );

    _contractWatchdog?.cancel();
    final timeout = Duration(
      seconds: config.durationTicks * 2 + 60 + _martingaleLevel * 30,
    );
    _contractWatchdog = Timer(timeout, () {
      if (!_inTrade || _disposed) return;
      onLog('AVISO: contrato #$contractId sem conclusao em ${timeout.inSeconds}s.');
      final id = _openContractId;
      if (id != null && api.isConnected) {
        api.sell(id).then((_) => onLog('Contrato #$id vendido a mercado.')).catchError((Object e) {
          onLog('Nao foi possivel vender #$id: $e');
          _releaseContractTracking();
        });
      } else {
        _releaseContractTracking();
      }
    });
  }

  void _closeTrade(double profit) {
    _releaseContractTracking();
    pnl += profit;
    if (profit >= 0) {
      wins++;
      _consecutiveLosses = 0;
      _martingaleLevel = 0;
      currentStake = config.baseStake;
      onLog('WIN +$profit | PnL: ${pnl.toStringAsFixed(2)}');
    } else {
      losses++;
      _consecutiveLosses++;
      if (config.useMartingale && _martingaleLevel < config.martingaleMaxLevels) {
        _martingaleLevel++;
        currentStake *= config.martingaleFactor;
        onLog(
          'LOSS $profit | PnL: ${pnl.toStringAsFixed(2)} '
          '(Martingale nivel $_martingaleLevel/${config.martingaleMaxLevels})',
        );
      } else {
        _martingaleLevel = 0;
        currentStake = config.baseStake;
        onLog('LOSS $profit | PnL: ${pnl.toStringAsFixed(2)}');
      }
    }
    onTradeClosed(BotTradeResult(profit: profit, pnl: pnl, wins: wins, losses: losses));

    _refreshBalance();

    if (pnl <= -config.maxDailyLoss.abs()) {
      stop('STOP LOSS diario atingido (${pnl.toStringAsFixed(2)})');
    } else if (pnl >= config.takeProfit) {
      stop('TAKE PROFIT atingido (${pnl.toStringAsFixed(2)})');
    } else if (_consecutiveLosses >= 5) {
      stop('5 perdas consecutivas. Bot pausado por seguranca.');
    } else if (totalTrades >= config.maxTrades) {
      stop('Limite de operacoes ($totalTrades/${config.maxTrades}) atingido.');
    }
  }

  Future<void> _refreshBalance() async {
    try {
      final account = await api.fetchAccount();
      onAccount(account);
    } catch (_) {}
  }

  void _releaseContractTracking() {
    _contractWatchdog?.cancel();
    _contractWatchdog = null;
    _contractSub?.cancel();
    _contractSub = null;
    _openContractId = null;
    if (!_stopping && !_disposed) _inTrade = false;
  }

  // ------------------------------------------------------------------
  // Reconexao
  // ------------------------------------------------------------------

  void _scheduleReconnect(String reason) {
    if (_stopping || _disposed) return;
    if (_reconnectTimer != null) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      stop('Conexao perdida ($reason). Limite de reconexoes atingido.',
          notify: true);
      return;
    }
    _reconnectAttempts++;
    final delay = Duration(seconds: 3 * _reconnectAttempts);
    onLog(
      'Conexao perdida ($reason). Reconectando em ${delay.inSeconds}s '
      '($_reconnectAttempts/$_maxReconnectAttempts)...',
    );
    _tickSub?.cancel();
    _tickSub = null;
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      if (_stopping || _disposed) return;
      try {
        await _openSessionSafely();
        await _subscribeTicks();
        _reconnectAttempts = 0;
        onLog('Reconectado com sucesso.');
      } catch (e) {
        onLog('Falha ao reconectar: $e');
        _scheduleReconnect('nova tentativa');
      }
    });
  }

  Future<void> _openSessionSafely() async {
    // Reaproveita o mesmo cliente REST/token para novo OTP + socket.
    api.dispose();
    await api.connect(
          token: config.token,
          appId: config.appId,
          accountType: config.accountType);
    final account = await api.fetchAccount();
    currency = account.currency;
    onAccount(account);
    await _recoverOpenContracts();
  }

  // ------------------------------------------------------------------
  // Parada
  // ------------------------------------------------------------------

  Future<void> stop(String reason, {bool notify = true}) async {
    if (_stopping) return;
    _stopping = true;
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _contractWatchdog?.cancel();

    final openId = _openContractId;
    if (openId != null && api.isConnected) {
      try {
        await api.sell(openId);
        onLog('Contrato #$openId vendido antes de parar.');
      } catch (e) {
        onLog('AVISO: contrato #$openId segue aberto (nao vendido): $e');
      }
    }

    await _tickSub?.cancel();
    await _contractSub?.cancel();
    await _recoverySub?.cancel();
    api.dispose();
    onLog('Bot parado: $reason');
    if (notify) onStopped(reason);
  }
}

class BotTradeResult {
  final double profit;
  final double pnl;
  final int wins;
  final int losses;
  const BotTradeResult({
    required this.profit,
    required this.pnl,
    required this.wins,
    required this.losses,
  });
}
