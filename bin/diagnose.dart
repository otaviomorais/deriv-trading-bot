// Diagnostico de conexao com a nova plataforma Deriv.
//
// Uso (na raiz do projeto, com Dart SDK instalado):
//   dart run bin/diagnose.dart <token_pat> <app_id> [simbolo]
//
// Replica exatamente o fluxo do app:
//   1. GET  /trading/v1/options/accounts          -> lista contas
//   2. POST /trading/v1/options/accounts/{id}/otp -> URL WS autenticada
//   3. Conecta e testa: ping, balance, ticks_history, subscribe ticks, proposal
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final token = args.isNotEmpty ? args[0] : '';
  final appId = args.length > 1 ? args[1] : '';
  final symbol = args.length > 2 ? args[2] : 'R_100';

  void ok(String m) => stdout.writeln('[OK]    $m');
  void fail(String m) => stdout.writeln('[FALHA] $m');
  void step(String m) => stdout.writeln('\n-- $m');

  stdout.writeln('============================================================');
  stdout.writeln('DIAGNOSTICO DERIV - nova plataforma');
  stdout.writeln(
      'Token: ${token.isEmpty ? "(vazio)" : "${token.substring(0, token.length.clamp(0, 8))}..."} '
      '| App-ID: ${appId.isEmpty ? "(vazio!)" : appId}');
  stdout.writeln('============================================================');

  if (token.isEmpty || appId.isEmpty) {
    fail('Uso: dart run bin/diagnose.dart <token> <app_id> [simbolo]');
    fail('Sem App ID registrado em developers.deriv.com nada funciona.');
    exit(1);
  }

  HttpClient? client;
  Future<Map<String, dynamic>> rest(String method, String path) async {
    client ??= HttpClient();
    final req = await client!.openUrl(method, Uri.parse('https://api.derivws.com$path'));
    req.headers.set('Authorization', 'Bearer $token');
    req.headers.set('Deriv-App-ID', appId);
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    final res = await req.close().timeout(const Duration(seconds: 20));
    final body = await utf8.decoder.bind(res).join();
    return {'status': res.statusCode, 'body': body};
  }

  // Etapa 1: contas
  step('[1/4] GET /trading/v1/options/accounts');
  Map<String, dynamic> accountsRes;
  try {
    accountsRes = await rest('GET', '/trading/v1/options/accounts');
  } catch (e) {
    fail('Erro de rede: $e');
    exit(1);
  }
  if (accountsRes['status'] != 200) {
    fail('HTTP ${accountsRes['status']}: ${accountsRes['body']}');
    if ('${accountsRes['body']}'.contains('Invalid application')) {
      stdout.writeln('        -> Este App ID nao existe na plataforma nova.');
      stdout.writeln('        -> Registre um app tipo PAT em developers.deriv.com');
      stdout.writeln('           (Dashboard > Applications > Register new app)');
    }
    exit(1);
  }
  final decoded = jsonDecode(accountsRes['body'] as String);
  var list = decoded['data'];
  if (list is Map) list = list['accounts'];
  if (list is! List || list.isEmpty) {
    fail('Nenhuma conta na resposta.');
    exit(1);
  }
  ok('${list.length} conta(s):');
  String chosen = '';
  for (final raw in list) {
    final a = raw as Map;
    final id = '${a['account_id'] ?? a['accountId'] ?? a['id']}';
    final virt = a['is_virtual'] == 1 || a['is_virtual'] == true;
    stdout.writeln(
        '        - $id [${virt ? "DEMO" : "REAL"}] ${a['balance']} ${a['currency']}');
    if (chosen.isEmpty || virt) chosen = id;
  }

  // Etapa 2: OTP
  step('[2/4] POST .../accounts/$chosen/otp');
  final otpRes = await rest('POST', '/trading/v1/options/accounts/$chosen/otp');
  if (otpRes['status'] != 200) {
    fail('HTTP ${otpRes['status']}: ${otpRes['body']}');
    stdout.writeln('        -> Escopo trade presente no token? Token revogado?');
    exit(1);
  }
  final wsUrl =
      ((jsonDecode(otpRes['body'] as String) as Map)['data'] as Map)['url'] as String?;
  if (wsUrl == null || wsUrl.isEmpty) {
    fail('OTP sem url.');
    exit(1);
  }
  ok('URL recebida (${wsUrl.contains('/demo') ? "demo" : "real"})');

  // Etapa 3: WebSocket
  step('[3/4] Conectando no WebSocket autenticado...');
  WebSocket? ws;
  try {
    ws = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 20));
  } catch (e) {
    fail('WebSocket: $e');
    exit(1);
  }
  ok('Conectado e AUTENTICADO (o OTP ja autoriza a sessao)');

  var reqId = 0;
  Future<Map<String, dynamic>> send(Map<String, dynamic> payload) async {
    payload['req_id'] = ++reqId;
    ws.add(jsonEncode(payload));
    final raw = await ws.first.timeout(const Duration(seconds: 15));
    return jsonDecode(raw as String) as Map<String, dynamic>;
  }

  try {
    step('[4/4] Testes de operacao');
    final pong = await send({'ping': 1});
    pong['error'] == null ? ok('ping') : fail('${pong['error']}');

    final bal = await send({'balance': 1});
    bal['error'] == null
        ? ok('balance: ${bal['balance']['balance']} ${bal['balance']['currency']}')
        : fail('balance: ${bal['error']}');

    final hist = await send({
      'ticks_history': symbol,
      'count': 5,
      'end': 'latest',
      'style': 'ticks',
    });
    hist['error'] == null
        ? ok('ticks_history $symbol: ${hist['history']['prices']}')
        : fail('ticks_history: ${hist['error']}');

    final tick = await send({'ticks': symbol, 'subscribe': 1});
    tick['error'] == null
        ? ok('tick ao vivo $symbol: ${tick['tick']['quote']}')
        : fail('subscribe ticks: ${tick['error']}');

    final prop = await send({
      'proposal': 1,
      'amount': 1,
      'basis': 'stake',
      'contract_type': 'CALL',
      'currency': 'USD',
      'duration': 5,
      'duration_unit': 't',
      'underlying_symbol': symbol,
    });
    if (prop['error'] == null) {
      final pid = prop['proposal']['id'];
      ok('proposal CALL id=${pid.toString().substring(0, 12)}... '
          '(spot ${prop['proposal']['spot']}, payout ${prop['proposal']['payout']})');
    } else {
      fail('proposal: ${prop['error']}');
    }

    stdout.writeln('\n============================================================');
    ok('TUDO FUNCIONANDO. Use o mesmo token+App ID no app.');
  } finally {
    await ws.close();
    client?.close();
  }
}
