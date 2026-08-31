import 'dart:async';
import 'dart:convert';

import '../models/bot_config.dart';
import '../services/deriv_api.dart';
import '../strategy/ml_strategy.dart';

enum BotStatus { idle, connecting, running, reconnecting, stopped, error }

/// Amostra de treino pendente: features no momento t, com desfecho conhecido
/// apenas `remaining` ticks depois (alvo alinhado a duracao do contrato).
class _PendingLabel {
  final List<double> features;
  final double entryPrice;
  int remaining;

  _PendingLabel(this.features, this.entryPrice, this.remaining);
}

class TradingBot {
  final DerivApi api;
  final MLStrategy strategy;

  BotConfig config;
  final void Function(String message) onLog;
  final void Function(double probability) onSignal;
  final void Function(AccountInfo account) onAccount;
  final void Function(BotTradeResult result) onTradeClosed;
  final void Function(String reason) onStopped;

  /// Persiste o modelo serializado para sobreviver a restarts do app.
  final Future<void> Function(String modelJson)? onModelChanged;

  /// Persiste o PnL acumulado do dia para o stop loss diario sobreviver a restarts.
  final Future<void> Function(String dayKey, double dailyPnl)? onDailyPnlChanged;

  static const int _maxReconnectAttempts = 5;

  /// Payout simulado (x stake) usado no paper trading.
  static const double _paperPayout = 0.95;

  final List<double> _closes = [];
  StreamSubscription<Map<String, dynamic>>? _tickSub;
  StreamSubscription<Map<String, dynamic>>? _contractSub;
  StreamSubscription<Map<String, dynamic>>? _recoverySub;
  Timer? _contractWatchdog;
  Timer? _reconnectTimer;
  bool _inTrade = false;
  bool _disposed = false;
  bool _wasWarm = false;

  final List<_PendingLabel> _pendingLabels = [];

  String currency = 'USD';

  double currentStake = 1.0;
  double pnl = 0;
  double dailyPnl = 0;
  String _dayKey;
  int wins = 0;
  int losses = 0;
  int totalTrades = 0;
  int _consecutiveLosses = 0;
  int _martingaleLevel = 0;
  int _cooldownRemaining = 0;
  bool _stopping = false;
  int _reconnectAttempts = 0;
  int? _openContractId;

  // Contrato simulado (paper trading).
  bool _paperActive = false;
  String _paperType = 'CALL';
  double _paperEntry = 0;
  double _paperStake = 0;
  int _paperTicksLeft = 0;

  TradingBot({
    required this.config,
    DerivApi? api,
    MLStrategy? strategy,
    String? modelJson,
    String? dayKey,
    this.dailyPnl = 0,
    required this.onLog,
    required this.onSignal,
    required this.onAccount,
    required this.onTradeClosed,
    required this.onStopped,
    this.onModelChanged,
    this.onDailyPnlChanged,
  })  : api = api ?? DerivApi(),
        strategy = strategy ?? MLStrategy.tryFromJson(modelJson ?? '') ?? MLStrategy(),
        _dayKey = dayKey ?? _todayKey() {
    _wasWarm = this.strategy.trainedSamples > 0;
    this.strategy.targetHorizon = config.durationTicks < 1 ? 1 : config.durationTicks;
    currentStake = config.baseStake;
    this.api.onDisconnected = (reason) => _scheduleReconnect(reason);
  }

  static String _todayKey() => DateTime.now().toIso8601String().substring(0, 10);

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
        onLog(
          'Treinando modelo com ${_closes.length} ticks '
          '(alvo: ${strategy.targetHorizon} ticks)...',
        );
        strategy.warmUp(_closes);
        _wasWarm = true;
        onLog('Modelo pronto (${strategy.trainedSamples} amostras).');
      } else {
        onLog('Modelo preservado (${strategy.trainedSamples} amostras).');
      }
      await _persistModel();

      await _subscribeTicks();

      _reconnectAttempts = 0;
      onLog(
        'Bot iniciado em ${config.symbol}${config.paperTrading ? " (PAPER)" : ""}. '
        'Limiar de entrada: ${(config.entryThreshold * 100).toStringAsFixed(0)}%. '
        'Aguardando sinais...',
      );
    } catch (e) {
      onLog('ERRO: $e');
      stop('Falha na inicializacao: $e', notify: true);
    }
  }

  Future<void> _recoverOpenContracts() async {
    final pendingId = _openContractId;
    final recovered = <int>{};
    try {
      _recoverySub?.cancel();
      _recoverySub = api.subscribeOpenContracts().listen((msg) {
        final c = msg['proposal_open_contract'] as Map<String, dynamic>?;
        if (c == null || c['is_sold'] == 1) return;
        final id = c['contract_id'] as int?;
        if (id == null) return;
        recovered.add(id);
        onLog('Contrato aberto recuperado #$id. Acompanhando ate o fim.');
        _adoptContract(id);
      });
      // Da tempo para o servidor responder com posicoes abertas.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      _recoverySub?.cancel();
      _recoverySub = null;
    } catch (_) {
      // Sem posicoes abertas ou endpoint indisponivel; segue o fluxo.
    }

    // Um contrato que estava aberto e sumiu durante a desconexao encerrou sem
    // o bot ver: registra a perda para o controle de risco continuar correto.
    if (pendingId != null &&
        !recovered.contains(pendingId) &&
        _openContractId == pendingId) {
      onLog(
        'Contrato #$pendingId encerrou durante a desconexao. '
        'Registrando perda do stake.',
      );
      _releaseContractTracking();
      _closeTrade(-currentStake);
    }
  }

  Future<void> _subscribeTicks() async {
    await _tickSub?.cancel();
    _tickSub = api.subscribeTicks(config.symbol).listen(
          _onTick,
          onError: (Object e) =>
              _scheduleReconnect('Erro no stream de ticks: $e'),
        );
  }

  void _onTick(Map<String, dynamic> msg) {
    if (_stopping || _disposed) return;
    final tick = msg['tick'] as Map<String, dynamic>?;
    if (tick == null) return;
    final quote = (tick['quote'] as num).toDouble();

    // 1) Amadurece amostras pendentes: treina com o desfecho real (N ticks).
    for (var i = _pendingLabels.length - 1; i >= 0; i--) {
      final p = _pendingLabels[i];
      p.remaining--;
      if (p.remaining <= 0) {
        strategy.train(p.features, quote > p.entryPrice);
        _pendingLabels.removeAt(i);
      }
    }

    // 2) Atualiza o buffer e agenda nova amostra para treino futuro.
    _closes.add(quote);
    if (_closes.length > 2000) {
      _closes.removeRange(0, _closes.length - 1500);
    }
    final features = strategy.buildFeatures(_closes);
    if (features == null) return;
    _pendingLabels.add(
      _PendingLabel(features, quote, strategy.targetHorizon),
    );

    if (_cooldownRemaining > 0) _cooldownRemaining--;

    // 3) Contrato simulado (paper trading): resolve por contagem de ticks.
    if (_paperActive) {
      _advancePaper(quote);
      if (_paperActive) return;
    }

    final probUp = strategy.predictProbability(features);
    onSignal(probUp);

    if (_inTrade || totalTrades >= config.maxTrades) return;
    if (_cooldownRemaining > 0) return;

    if (probUp >= config.entryThreshold) {
      _openTrade('CALL', probUp);
    } else if (probUp <= 1 - config.entryThreshold) {
      _openTrade('PUT', 1 - probUp);
    }
  }

  Future<void> _openTrade(String contractType, double prob) async {
    _inTrade = true;
    totalTrades++;
    onLog(
      'SINAL ${(prob * 100).toStringAsFixed(1)}% -> $contractType '
      '| Stake: ${currentStake.toStringAsFixed(2)} $currency',
    );

    if (config.paperTrading) {
      _openPaperContract(contractType);
      return;
    }

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

  void _openPaperContract(String contractType) {
    _paperActive = true;
    _paperType = contractType;
    _paperEntry = _closes.last;
    _paperStake = currentStake;
    _paperTicksLeft = config.durationTicks < 1 ? 1 : config.durationTicks;
    onLog(
      'PAPER: contrato $contractType aberto '
      '(stake ${currentStake.toStringAsFixed(2)} $currency). '
      'Resolve em $_paperTicksLeft ticks.',
    );
  }

  void _advancePaper(double quote) {
    _paperTicksLeft--;
    if (_paperTicksLeft > 0) return;
    final won = _paperType == 'CALL' ? quote > _paperEntry : quote < _paperEntry;
    final profit = won ? _paperStake * _paperPayout : -_paperStake;
    onLog(
      'PAPER: contrato encerrado -> ${won ? "WIN" : "LOSS"} '
      '${profit >= 0 ? "+" : ""}${profit.toStringAsFixed(2)}',
    );
    _paperActive = false;
    _closeTrade(profit);
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
    _contractWatchdog = Timer(timeout, () async {
      if (!_inTrade || _disposed) return;
      final id = _openContractId;
      if (id == null) {
        _releaseContractTracking();
        return;
      }
      if (!api.isConnected) {
        // Mantem o rastreio; a reconexao (_recoverOpenContracts) resolve.
        onLog(
          'AVISO: conexao indisponivel. Contrato #$id sera '
          'recuperado na reconexao.',
        );
        return;
      }
      onLog('AVISO: contrato #$id sem conclusao em ${timeout.inSeconds}s.');
      try {
        final open = await api.fetchOpenContract(id);
        final stillOpen =
            open != null && (open['is_sold'] == 0 || open['is_sold'] == null);
        if (stillOpen) {
          // Ainda aberto a mercado: tenta vender para nao ficar pendurado.
          try {
            await api.sell(id);
            onLog('Contrato #$id vendido a mercado.');
          } catch (e) {
            // Sumiu entre a consulta e a venda => ja encerrou. Sem erro.
            onLog('Contrato #$id encerrou antes da venda.');
            _releaseContractTracking();
          }
          return;
        }
        // Ja nao esta aberto: registra o desfecho se o servidor reportou.
        final sold = open != null && open['is_sold'] == 1;
        final profit = (open?['profit'] as num?)?.toDouble() ?? 0;
        if (sold && profit != 0) {
          _closeTrade(profit);
        } else {
          onLog('Contrato #$id encerrou automaticamente.');
          _releaseContractTracking();
        }
      } catch (_) {
        onLog('Nao foi possivel consultar o contrato #$id.');
        _releaseContractTracking();
      }
    });
  }

  void _closeTrade(double profit) {
    _releaseContractTracking();

    // PnL do dia com persistencia: sobrevive a restart do app.
    final key = _todayKey();
    if (key != _dayKey) {
      _dayKey = key;
      dailyPnl = 0;
    }
    dailyPnl += profit;
    unawaited(onDailyPnlChanged?.call(_dayKey, dailyPnl));
    unawaited(onModelChanged?.call(jsonEncode(strategy.toJson())));

    pnl += profit;
    if (profit >= 0) {
      wins++;
      _consecutiveLosses = 0;
      _martingaleLevel = 0;
      currentStake = config.baseStake;
      onLog('WIN +${profit.toStringAsFixed(2)} | PnL: ${pnl.toStringAsFixed(2)}');
    } else {
      losses++;
      _consecutiveLosses++;
      if (config.useMartingale &&
          _martingaleLevel < config.martingaleMaxLevels) {
        _martingaleLevel++;
        currentStake *= config.martingaleFactor;
        onLog(
          'LOSS ${profit.toStringAsFixed(2)} | PnL: ${pnl.toStringAsFixed(2)} '
          '(Martingale nivel $_martingaleLevel/${config.martingaleMaxLevels})',
        );
      } else {
        _martingaleLevel = 0;
        currentStake = config.baseStake;
        onLog('LOSS ${profit.toStringAsFixed(2)} | PnL: ${pnl.toStringAsFixed(2)}');
      }
    }
    _cooldownRemaining = config.cooldownTicks < 0 ? 0 : config.cooldownTicks;
    onTradeClosed(
      BotTradeResult(
        profit: profit,
        pnl: pnl,
        dailyPnl: dailyPnl,
        wins: wins,
        losses: losses,
      ),
    );

    _refreshBalance();

    if (dailyPnl <= -config.maxDailyLoss.abs()) {
      stop('STOP LOSS diario atingido (${dailyPnl.toStringAsFixed(2)})');
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
    _contractWatchdog = null;

    final openId = _openContractId;

    if (openId != null && openId > 0 && api.isConnected && !config.paperTrading) {
      if (config.durationTicks <= 30) {
        // Contrato curto: vender agora costuma realizar a maior parte da
        // perda. Deixa expirar (poucos segundos) e registra o resultado real.
        onLog(
          'Contrato #$openId tem curta duracao; aguardando expiracao '
          'em vez de vender...',
        );
        await _waitForContractResolution(openId);
      } else {
        try {
          await api.sell(openId);
          onLog('Contrato #$openId vendido antes de parar.');
        } catch (e) {
          onLog('AVISO: contrato #$openId segue aberto (nao vendido): $e');
        }
      }
    }

    await _tickSub?.cancel();
    await _contractSub?.cancel();
    await _recoverySub?.cancel();
    _tickSub = null;
    _contractSub = null;
    _recoverySub = null;
    api.dispose();
    unawaited(onModelChanged?.call(jsonEncode(strategy.toJson())));
    onLog('Bot parado: $reason');
    if (notify) onStopped(reason);
  }

  /// Espera (com limite) um contrato curto resolver sozinho no subscribe.
  Future<void> _waitForContractResolution(int id) async {
    final deadline = DateTime.now().add(
      Duration(seconds: config.durationTicks * 2 + 120),
    );
    while (_openContractId == id && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (_openContractId == id) {
      onLog(
        'AVISO: contrato #$id nao resolveu a tempo. '
        'Sera recuperado no proximo start.',
      );
      _releaseContractTracking();
    } else {
      onLog('Contrato #$id encerrado. Parada concluida.');
    }
  }

  Future<void> _persistModel() async {
    try {
      await onModelChanged?.call(jsonEncode(strategy.toJson()));
    } catch (_) {}
  }
}

class BotTradeResult {
  final double profit;
  final double pnl;
  final double dailyPnl;
  final int wins;
  final int losses;
  const BotTradeResult({
    required this.profit,
    required this.pnl,
    required this.dailyPnl,
    required this.wins,
    required this.losses,
  });
}