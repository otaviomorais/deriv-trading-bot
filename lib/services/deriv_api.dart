import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class DerivApiException implements Exception {
  final String message;
  DerivApiException(this.message);
  @override
  String toString() => message;
}

class DerivApi {
  static const String appId = '1089';
  WebSocketChannel? _channel;
  int _reqId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final Map<int, void Function(Map<String, dynamic>)> _subscriptions = {};

  bool get isConnected => _channel != null;

  Future<void> connect() async {
    final uri = Uri.parse('wss://ws.derivws.com/websockets/v3?app_id=$appId');
    _channel = WebSocketChannel.connect(uri);
    await _channel!.ready;
    _channel!.stream.listen(
      (data) => _handleMessage(data as String),
      onError: (Object e) => _failAll('Conexao perdida: $e'),
      onDone: () => _failAll('Conexao fechada'),
      cancelOnError: true,
    );
  }

  void _handleMessage(String raw) {
    final msg = jsonDecode(raw) as Map<String, dynamic>;
    final reqId = msg['req_id'] as int?;
    if (reqId == null) return;
    if (_pending.containsKey(reqId)) {
      final completer = _pending.remove(reqId)!;
      if (msg['error'] != null) {
        completer.completeError(DerivApiException(msg['error']['message'] as String));
      } else {
        completer.complete(msg);
      }
    } else if (_subscriptions.containsKey(reqId)) {
      if (msg['error'] == null) {
        _subscriptions[reqId]!(msg);
      }
    }
  }

  void _failAll(String reason) {
    for (final c in _pending.values) {
      c.completeError(DerivApiException(reason));
    }
    _pending.clear();
  }

  Future<Map<String, dynamic>> request(Map<String, dynamic> payload) {
    if (!isConnected) throw DerivApiException('Nao conectado');
    final id = ++_reqId;
    payload['req_id'] = id;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _channel!.sink.add(jsonEncode(payload));
    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _pending.remove(id);
        throw DerivApiException('Timeout na requisicao');
      },
    );
  }

  Stream<Map<String, dynamic>> subscribe(Map<String, dynamic> payload) {
    if (!isConnected) throw DerivApiException('Nao conectado');
    final id = ++_reqId;
    payload['req_id'] = id;
    final controller = StreamController<Map<String, dynamic>>();
    _subscriptions[id] = controller.add;
    _channel!.sink.add(jsonEncode(payload));
    return controller.stream;
  }

  Future<Map<String, dynamic>> authorize(String token) async {
    final res = await request({'authorize': token});
    return res['authorize'] as Map<String, dynamic>;
  }

  Future<double> fetchBalance(String currency) async {
    final res = await request({'balance': 1});
    final b = res['balance'] as Map<String, dynamic>;
    return (b['balance'] as num).toDouble();
  }

  Future<List<double>> fetchTicksHistory(String symbol, {int count = 1000}) async {
    final res = await request({
      'ticks_history': symbol,
      'adjust_start_time': 1,
      'count': count,
      'end': 'latest',
      'style': 'ticks',
    });
    final history = res['history'] as Map<String, dynamic>;
    final prices = (history['prices'] as List).cast<num>();
    return prices.map((p) => p.toDouble()).toList();
  }

  Future<int> buyContract({
    required String contractType,
    required double stake,
    required int duration,
    required String symbol,
  }) async {
    final res = await request({
      'buy': '1',
      'price': stake,
      'parameters': {
        'amount': stake,
        'basis': 'stake',
        'contract_type': contractType,
        'currency': 'USD',
        'duration': duration,
        'duration_unit': 't',
        'symbol': symbol,
      },
    });
    final buy = res['buy'] as Map<String, dynamic>;
    return buy['contract_id'] as int;
  }

  Stream<Map<String, dynamic>> subscribeContract(int contractId) {
    return subscribe({'proposal_open_contract': 1, 'contract_id': contractId});
  }

  void dispose() {
    _failAll('Cliente encerrado');
    _subscriptions.clear();
    _channel?.sink.close();
    _channel = null;
  }
}
