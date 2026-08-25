import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bot/trading_bot.dart';
import '../state/bot_state.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BotState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deriv AI Bot'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label:
                        'Saldo (${state.accountIsVirtual ? "DEMO" : "REAL"})',
                    value:
                        '${state.balance.toStringAsFixed(2)} ${state.currency}',
                    color: Colors.blueAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    label: 'PnL',
                    value:
                        '${state.pnl >= 0 ? '+' : ''}\$${state.pnl.toStringAsFixed(2)}',
                    color: state.pnl >= 0 ? Colors.greenAccent : Colors.redAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    label: 'Wins/Losses',
                    value: '${state.wins}/${state.losses}',
                    color: Colors.amberAccent,
                  ),
                ),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Sinal atual: ${state.lastSignal}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: state.lastProbability,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('BAIXA', style: TextStyle(color: Colors.redAccent)),
                      Text(
                        '${(state.lastProbability * 100).toStringAsFixed(1)}% ALTA',
                        style: const TextStyle(color: Colors.greenAccent),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              state.status == BotStatus.reconnecting
                  ? 'Status: RECONECTANDO (${state.config.symbol})'
                  : state.isRunning
                      ? 'Status: OPERANDO (${state.config.symbol})'
                      : 'Status: PARADO',
              style: TextStyle(
                color: state.isRunning ? Colors.greenAccent : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(8),
                itemCount: state.logs.length,
                itemBuilder: (_, i) =>
                    Text(state.logs[state.logs.length - 1 - i],
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        state.isRunning ? Colors.redAccent : Colors.green,
                  ),
                  icon: Icon(state.isRunning ? Icons.stop : Icons.play_arrow),
                  label: Text(state.isRunning ? 'PARAR BOT' : 'INICIAR BOT'),
                  onPressed: () {
                    final missing = state.missingCredentials;
                    if (missing.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(missing)));
                      return;
                    }
                    state.isRunning ? state.stop() : state.start();
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
