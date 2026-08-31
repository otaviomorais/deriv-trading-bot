import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/bot_config.dart';

/// Plataforma nova da Deriv devolve numericos como string|number.
double _asDouble(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

class DerivApiException implements Exception {
  final String message;
  final String? code;
  const DerivApiException(this.message, {this.code});
  @override
  String toString() => code == null ? message : '$code: $message';
}

class AccountInfo {
  final String accountId;
  final bool isVirtual;
  final String currency;
  final double balance;

  const AccountInfo({
    required this.accountId,
    required this.isVirtual,
    required this.currency,
    required this.balance,
  });
}

class BarrierProposal {
  final String proposalId;
  /// Barreira relativa ao spot no formato da API (ex.: '-12.5000').
  final String barrier;
  /// Retorno esperado em % se vencer: (payout - stake) / stake * 100.
  final double returnPct;
  final double payout;
  final double spot;
  const BarrierProposal({
    required this.proposalId,
    required this.barrier,
    required this.returnPct,
    required this.payout,
    required this.spot,
  });
}

class BarrierContractResult {
  final int contractId;
  final BarrierProposal proposal;
  const BarrierContractResult({
    required this.contractId,
    required this.proposal,
  });
}

class _Subscription {
  final StreamController<Map<String, dynamic>> controller;
  final Map<String, dynamic> payload;
  String? streamId;

  _Subscription(this.controller, this.payload);
}

class DerivApi {
  static const String apiBase = 'https://api.derivws.com';

  WebSocketChannel? _channel;
  http.Client? _http;
  int _reqId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final Map<int, _Subscription> _subscriptions = {};
  StreamSubscription<dynamic>? _socketSub;

  String _token = '';
  String _preferredAccountType = BotConfig.accountDemo;
  String _appId = '';

  /// Callback acionado quando a conexão cai inesperadamente.
  void Function(String reason)? onDisconnected;

  bool get isConnected => _channel != null && !_isClosing;

  bool _isClosing = false;
  Timer? _heartbeat;

  Future<void> connect({
    required String token,
    required String appId,
    String accountType = BotConfig.accountDemo,
  }) async {
    if (token.trim().isEmpty) {
      throw const DerivApiException('Token vazio');
    }
    if (appId.trim().isEmpty) {
      throw const DerivApiException(
        'App ID vazio. Registre um app (tipo PAT) em developers.deriv.com '
        'e cole o App ID nas configuracoes.',
      );
    }
    _token = token.trim();
    _appId = appId.trim();
    _preferredAccountType =
        accountType == BotConfig.accountReal ? BotConfig.accountReal : BotConfig.accountDemo;
    await _openSession();
  }

  Future<void> _openSession() async {
    _isClosing = false;
    final accountId = await _resolveAccountId();
    final wsUrl = await _requestOtpUrl(accountId);
    await _connectSocket(wsUrl);
  }

  /// Conta demo na plataforma nova usa prefixo DOT; conta real, ROT.
  static bool isDemoAccountId(String id) {
    final upper = id.toUpperCase();
    if (upper.startsWith('DOT')) return true;
    if (upper.startsWith('ROT')) return false;
    // Fallback para o flag, quando presente.
    return false;
  }

  Future<String> _resolveAccountId() async {
    final accounts = await _restRequest(
      method: 'GET',
      path: '/trading/v1/options/accounts',
    );
    final data = accounts['data'];
    final list = data is List ? data : (data?['accounts'] as List?);
    if (list == null || list.isEmpty) {
      throw const DerivApiException('Nenhuma conta encontrada neste token.');
    }

    String idOf(Map<dynamic, dynamic> a) =>
        (a['account_id'] ?? a['accountId'] ?? a['loginid'] ?? a['id'] ?? '')
            .toString();

    bool isDemo(Map<dynamic, dynamic> a) {
      final flag = a['is_virtual'] ?? a['isVirtual'];
      if (flag == 1 || flag == true) return true;
      if (flag == 0 || flag == false) return false;
      return isDemoAccountId(idOf(a));
    }

    final wantDemo = _preferredAccountType != BotConfig.accountReal;
    for (final raw in list) {
      final a = raw as Map<dynamic, dynamic>;
      if (isDemo(a) == wantDemo) {
        final id = idOf(a);
        if (id.isNotEmpty) return id;
      }
    }
    throw DerivApiException(
      'Conta ${wantDemo ? "DEMO" : "REAL"} nao encontrada no seu token. '
      'Contas disponiveis: ${list.map((e) => idOf(e as Map<dynamic, dynamic>)).join(", ")}.',
    );
  }

  Future<String> _requestOtpUrl(String accountId) async {
    final res = await _restRequest(
      method: 'POST',
      path: '/trading/v1/options/accounts/$accountId/otp',
    );
    final url = res['data']?['url'] as String?;
    if (url == null || url.isEmpty) {
      throw const DerivApiException('OTP nao retornou URL de WebSocket.');
    }
    return url;
  }

  Future<Map<String, dynamic>> _restRequest({
    required String method,
    required String path,
  }) async {
    _http ??= http.Client();
    late final http.Response res;
    try {
      final uri = Uri.parse('$apiBase$path');
      final req = http.Request(method, uri)
        ..headers.addAll({
          'Authorization': 'Bearer $_token',
          'Deriv-App-ID': _appId,
          'Content-Type': 'application/json',
        });
      res = await http.Response.fromStream(
        await _http!.send(req).timeout(const Duration(seconds: 20)),
      );
    } on TimeoutException {
      throw const DerivApiException('Timeout na chamada REST da Deriv.');
    } catch (e) {
      throw DerivApiException('Falha de rede na API REST: $e');
    }
    final body = res.body.isNotEmpty
        ? jsonDecode(res.body) as Map<String, dynamic>
        : <String, dynamic>{};
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final raw = _extractRestError(body) ?? 'HTTP ${res.statusCode} em $path';
      var msg = raw;
      if (raw.contains('Invalid application')) {
        msg = '$raw — este App ID nao esta registrado na plataforma nova '
            '(developers.deriv.com > Dashboard > Applications). App IDs '
            'antigos como 1089 nao funcionam.';
      } else if (res.statusCode == 401) {
        msg = '$raw — confira o token PAT e o App ID nas configuracoes.';
      }
      throw DerivApiException(msg, code: 'HTTP${res.statusCode}');
    }
    return body;
  }

  String? _extractRestError(Map<String, dynamic> body) {
    final errors = body['errors'];
    if (errors is List && errors.isNotEmpty) {
      final first = errors.first;
      if (first is Map) {
        final msg = first['message'];
        final code = first['code'];
        if (msg != null) return code == null ? '$msg' : '$code: $msg';
      }
    }
    return body['message'] as String?;
  }

  Future<void> _connectSocket(String url) async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      await _channel!.ready.timeout(const Duration(seconds: 20));
    } catch (e) {
      _channel = null;
      throw DerivApiException('Falha ao conectar no WebSocket: $e');
    }
    _socketSub = _channel!.stream.listen(
      _handleMessage,
      onError: (Object e) => _handleDisconnect('Erro no socket: $e'),
      onDone: () => _handleDisconnect('Conexao fechada pela Deriv'),
      cancelOnError: false,
    );
    _startHeartbeat();
  }

  /// Mantem o socket vivo: a Deriv fecha conexoes ociosas. Ping sem req_id;
  /// o pong volta sem req_id e e ignorado por _handleMessage.
  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!isConnected) return;
      try {
        _channel?.sink.add(jsonEncode({'ping': 1}));
      } catch (_) {}
    });
  }

  void _handleDisconnect(String reason) {
    if (_isClosing || !isConnected) return;
    _failPending(reason);
    for (final sub in _subscriptions.values) {
      sub.controller.addError(DerivApiException(reason));
      sub.controller.close();
    }
    _subscriptions.clear();
    _channel = null;
    onDisconnected?.call(reason);
  }

  void _handleMessage(dynamic raw) {
    if (raw is! String) return;
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final reqId = msg['req_id'] as int?;
    if (reqId == null) return;

    final pending = _pending.remove(reqId);
    if (pending != null) {
      final error = msg['error'];
      if (error != null) {
        pending.completeError(DerivApiException(
          error['message']?.toString() ?? 'Erro desconhecido',
          code: error['code']?.toString(),
        ));
      } else {
        pending.complete(msg);
      }
      return;
    }

    final sub = _subscriptions[reqId];
    if (sub != null) {
      final error = msg['error'];
      if (error != null) {
        _subscriptions.remove(reqId);
        sub.controller.addError(DerivApiException(
          error['message']?.toString() ?? 'Erro desconhecido',
          code: error['code']?.toString(),
        ));
        sub.controller.close();
      } else {
        final sid = msg['subscription'];
        if (sid is Map && sub.streamId == null) {
          sub.streamId = sid['id']?.toString();
        } else if (sid is String && sub.streamId == null) {
          sub.streamId = sid;
        }
        sub.controller.add(msg);
      }
    }
  }

  void _failPending(String reason) {
    for (final c in _pending.values) {
      c.completeError(DerivApiException(reason));
    }
    _pending.clear();
  }

  Future<Map<String, dynamic>> request(Map<String, dynamic> payload) {
    if (!isConnected) throw const DerivApiException('Nao conectado');
    final id = ++_reqId;
    payload['req_id'] = id;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _channel!.sink.add(jsonEncode(payload));
    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _pending.remove(id);
        throw const DerivApiException('Timeout na requisicao');
      },
    );
  }

  Stream<Map<String, dynamic>> subscribe(Map<String, dynamic> payload) {
    if (!isConnected) throw const DerivApiException('Nao conectado');
    final id = ++_reqId;
    payload['req_id'] = id;
    final controller = StreamController<Map<String, dynamic>>(
      onCancel: () => forgetByReqId(id),
    );
    final sub = _Subscription(controller, payload);
    _subscriptions[id] = sub;
    _channel!.sink.add(jsonEncode(payload));
    return controller.stream;
  }

  /// Envia `forget` para encerrar uma assinatura no servidor.
  Future<void> forgetByReqId(int reqId) async {
    final sub = _subscriptions.remove(reqId);
    if (sub == null) return;
    final sid = sub.streamId;
    if (sid == null || !isConnected) return;
    try {
      await request({'forget': sid});
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Operacoes de alto nivel
  // ------------------------------------------------------------------

  Future<AccountInfo> fetchAccount() async {
    final res = await request({'balance': 1});
    final b = res['balance'] as Map<String, dynamic>;
    final accountId = (b['loginid'] ?? b['account_id'] ?? '').toString();
    return AccountInfo(
      accountId: accountId,
      // Na plataforma nova, contas demo usam prefixo DOT; contas reais ROT.
      isVirtual: b['is_virtual'] == 1 ||
          b['is_virtual'] == true ||
          accountId.startsWith('DOT'),
      currency: (b['currency'] ?? 'USD').toString(),
      balance: _asDouble(b['balance']),
    );
  }

  Future<List<double>> fetchTicksHistory(
    String symbol, {
    int count = 1000,
  }) async {
    final res = await request({
      'ticks_history': symbol,
      'adjust_start_time': 1,
      'count': count,
      'end': 'latest',
      'style': 'ticks',
    });
    final history = res['history'] as Map<String, dynamic>;
    final prices = history['prices'] as List;
    return prices.map((p) => _asDouble(p)).toList();
  }

  Stream<Map<String, dynamic>> subscribeTicks(String symbol) {
    return subscribe({'ticks': symbol, 'subscribe': 1});
  }

  /// Pede um preco (proposal). Retorna o id usado para comprar.
  Future<String> fetchProposal({
    required String contractType,
    required double stake,
    required int duration,
    required String symbol,
    required String currency,
  }) async {
    final res = await request({
      'proposal': 1,
      'amount': stake,
      'basis': 'stake',
      'contract_type': contractType,
      'currency': currency,
      'duration': duration,
      'duration_unit': 't',
      // Na API nova o campo e underlying_symbol (nao symbol).
      'underlying_symbol': symbol,
    });
    final p = res['proposal'] as Map<String, dynamic>;
    return p['id'] as String;
  }

  /// Fluxo documentado da plataforma nova: proposal -> buy pelo ID.
  Future<int> buyContract({
    required String contractType,
    required double stake,
    required int duration,
    required String symbol,
    required String currency,
  }) async {
    final proposalId = await fetchProposal(
      contractType: contractType,
      stake: stake,
      duration: duration,
      symbol: symbol,
      currency: currency,
    );
    final res = await request({
      'buy': proposalId,
      'price': stake,
    });
    final buy = res['buy'] as Map<String, dynamic>;
    return buy['contract_id'] as int;
  }

  /// Spot atual do simbolo (para fallback de barreira absoluta).
  Future<double> fetchSpot(String symbol) async {
    final res = await request({
      'ticks_history': symbol,
      'adjust_start_time': 1,
      'count': 1,
      'end': 'latest',
      'style': 'ticks',
    });
    final history = res['history'] as Map<String, dynamic>;
    final prices = history['prices'] as List;
    return prices.isEmpty ? 0 : _asDouble(prices.last);
  }

  Map<String, dynamic> _ensureProposal(Map<String, dynamic> res) {
    final p = res['proposal'] as Map<String, dynamic>?;
    if (p == null || p['id'] == null) {
      throw const DerivApiException('Proposal higher/lower sem id.');
    }
    return p;
  }

  /// Propoe um higher/lower usando o proprio tipo do sinal (CALL/PUT) com
  /// barreira de margem: CALL -> barreira NEGATIVA (abaixo do spot);
  /// PUT -> barreira POSITIVA (acima do spot). Tenta barreira relativa
  /// (+/-) e, se a API recusar, barreira absoluta a partir do spot.
  Future<Map<String, dynamic>> _proposeWithBarrier({
    required String contractType,
    required double stake,
    required int duration,
    required String symbol,
    required String currency,
    required double offset,
    double? spot,
  }) async {
    final sign = contractType == 'CALL' ? -1.0 : 1.0;

    Map<String, dynamic> call(String barrier) => {
          'proposal': 1,
          'amount': stake,
          'basis': 'stake',
          'contract_type': contractType,
          'currency': currency,
          'duration': duration,
          'duration_unit': 't',
          'underlying_symbol': symbol,
          'barrier': barrier,
        };

    Object? lastErr;
    try {
      return _ensureProposal(
          await request(call((sign * offset).toStringAsFixed(4))));
    } catch (e) {
      lastErr = e;
    }
    if (spot != null && spot > 0) {
      try {
        return _ensureProposal(
            await request(call((spot + sign * offset).toStringAsFixed(4))));
      } catch (e) {
        lastErr = e;
      }
    }
    if (lastErr is DerivApiException) throw lastErr;
    throw const DerivApiException('Proposal higher/lower recusado.');
  }

  /// Encontra a barreira que entrega ~targetReturnPct% de retorno.
  ///
  /// CALL usa barreira NEGATIVA (abaixo do spot = margem para sinal CALL);
  /// PUT usa barreira POSITIVA (acima do spot = margem para sinal PUT).
  ///
  /// Busca binaria: o retorno cai monotonicamente quanto maior a margem
  /// (barreira mais "facil"). O erro real da API e preservado no log.
  Future<BarrierProposal> findBarrierForReturn({
    required String contractType,
    required double stake,
    required int duration,
    required String symbol,
    required String currency,
    required double targetReturnPct,
    double? currentSpot,
  }) async {
    double returnPctOf(Map<String, dynamic> p) {
      final payout = _asDouble(p['payout']);
      return stake > 0 ? (payout - stake) / stake * 100 : 0.0;
    }

    double? spot =
        (currentSpot != null && currentSpot > 0) ? currentSpot : null;
    if (spot == null) {
      try {
        spot = await fetchSpot(symbol);
      } catch (_) {}
    }

    String? lastErr;
    Future<BarrierProposal?> probe(double offset) async {
      final relBarrier = (contractType == 'CALL' ? -1.0 : 1.0) * offset;
      try {
        final p = await _proposeWithBarrier(
          contractType: contractType,
          stake: stake,
          duration: duration,
          symbol: symbol,
          currency: currency,
          offset: offset,
          spot: spot,
        );
        return BarrierProposal(
          proposalId: p['id'] as String,
          barrier: relBarrier.toStringAsFixed(4),
          returnPct: returnPctOf(p),
          payout: _asDouble(p['payout']),
          spot: _asDouble(p['spot']),
        );
      } catch (e) {
        lastErr = e is DerivApiException ? e.toString() : '$e';
        return null;
      }
    }

    // Ancoragem ~ no spot (retorno maximo possivel para o alvo).
    BarrierProposal? anchor;
    for (final off in const [0.0, 0.01, 0.1, 1.0, 5.0]) {
      anchor = await probe(off);
      if (anchor != null) break;
    }
    if (anchor == null) {
      throw DerivApiException(
        'Nao foi possivel propor o higher/lower ($contractType '
        '${duration}t $symbol): ${lastErr ?? 'resposta invalida'}',
      );
    }
    if (anchor.returnPct <= targetReturnPct) {
      // Mesmo na barreira do spot o retorno ja e menor que o alvo.
      return anchor;
    }

    double lo = 0;
    final baseSpot = anchor.spot > 0 ? anchor.spot : (spot ?? 0);
    double hi = baseSpot * 0.02; // margem maxima: 2% do spot
    if (hi <= 0) hi = 1.0;
    BarrierProposal best = anchor;
    for (var i = 0; i < 14; i++) {
      final mid = (lo + hi) / 2;
      final p = await probe(mid);
      if (p == null) break;
      if ((p.returnPct - targetReturnPct).abs() <
          (best.returnPct - targetReturnPct).abs()) {
        best = p;
      }
      if (p.returnPct > targetReturnPct) {
        lo = mid; // precisa de mais margem para reduzir o retorno
      } else {
        hi = mid; // passou do alvo
      }
    }
    return best;
  }

  /// Compra um higher/lower com a barreira calculada para o retorno alvo.
  Future<BarrierContractResult> buyHigherLower({
    required String contractType,
    required double stake,
    required int duration,
    required String symbol,
    required String currency,
    required double targetReturnPct,
    double? currentSpot,
  }) async {
    final proposal = await findBarrierForReturn(
      contractType: contractType,
      stake: stake,
      duration: duration,
      symbol: symbol,
      currency: currency,
      targetReturnPct: targetReturnPct,
      currentSpot: currentSpot,
    );
    final res = await request({
      'buy': proposal.proposalId,
      'price': stake,
    });
    final buy = res['buy'] as Map<String, dynamic>;
    return BarrierContractResult(
      contractId: buy['contract_id'] as int,
      proposal: proposal,
    );
  }

  Stream<Map<String, dynamic>> subscribeContract(int contractId) {
    return subscribe({
      'proposal_open_contract': 1,
      'contract_id': contractId,
      'subscribe': 1,
    });
  }

  /// Assina todas as posicoes abertas (recuperacao apos reinicio).
  Stream<Map<String, dynamic>> subscribeOpenContracts() {
    return subscribe({'proposal_open_contract': 1, 'subscribe': 1});
  }

  /// Consulta o estado atual de um contrato (sem subscribe). Retorna o
  /// contrato se ainda estiver aberto; null se ja nao existir entre as
  /// posicoes abertas (ex: ja expirou/foi vendido; a API retorna erro nesse
  /// caso, tratado aqui como encerrado).
  Future<Map<String, dynamic>?> fetchOpenContract(int contractId) async {
    try {
      final res = await request({
        'proposal_open_contract': 1,
        'contract_id': contractId,
      });
      return res['proposal_open_contract'] as Map<String, dynamic>?;
    } on DerivApiException {
      // A API retorna erro (ex: ContractNotFound) quando o contrato nao esta
      // mais aberto. Para o watchdog isso significa "ja encerrou".
      return null;
    }
  }

  Future<void> sell(int contractId, {double price = 0}) async {
    await request({'sell': contractId, 'price': price});
  }

  void dispose() {
    _isClosing = true;
    _heartbeat?.cancel();
    _heartbeat = null;
    for (final sub in _subscriptions.values) {
      unawaited(sub.controller.close());
    }
    _subscriptions.clear();
    _failPending('Cliente encerrado');
    _socketSub?.cancel();
    unawaited(_channel?.sink.close());
    _channel = null;
    _http?.close();
    _http = null;
  }
}
