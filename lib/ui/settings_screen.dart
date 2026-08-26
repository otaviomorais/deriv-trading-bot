import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/bot_config.dart';
import '../state/bot_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _token;
  late final TextEditingController _appId;
  late final TextEditingController _stake;
  late final TextEditingController _maxLoss;
  late final TextEditingController _takeProfit;
  late final TextEditingController _maxTrades;

  late String _symbol;
  late String _accountType;
  late double _threshold;
  late int _duration;
  late bool _martingale;
  late int _martingaleLevels;

  static const _symbols = {
    'R_10': 'Volatility 10',
    'R_25': 'Volatility 25',
    'R_50': 'Volatility 50',
    'R_75': 'Volatility 75',
    'R_100': 'Volatility 100',
    '1HZ100V': 'Volatility 100 (1s)',
  };

  @override
  void initState() {
    super.initState();
    final cfg = context.read<BotState>().config;
    _token = TextEditingController(text: cfg.token);
    _appId = TextEditingController(text: cfg.appId);
    _stake = TextEditingController(text: cfg.baseStake.toString());
    _maxLoss = TextEditingController(text: cfg.maxDailyLoss.toString());
    _takeProfit = TextEditingController(text: cfg.takeProfit.toString());
    _maxTrades = TextEditingController(text: cfg.maxTrades.toString());
    _symbol = cfg.symbol;
    _accountType = cfg.accountType;
    _threshold = cfg.entryThreshold;
    _duration = cfg.durationTicks;
    _martingale = cfg.useMartingale;
    _martingaleLevels = cfg.martingaleMaxLevels;
  }

  @override
  void dispose() {
    _token.dispose();
    _appId.dispose();
    _stake.dispose();
    _maxLoss.dispose();
    _takeProfit.dispose();
    _maxTrades.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuracoes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Token PAT da Deriv',
              border: OutlineInputBorder(),
              helperText:
                  'developers.deriv.com > Dashboard > API tokens > criar PAT '
                  '(escopos read + trade)',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _appId,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'App ID (nova plataforma)',
              border: OutlineInputBorder(),
              helperText:
                  'developers.deriv.com > Dashboard > registrar app do tipo '
                  'PAT e copiar o App ID gerado',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _accountType,
            decoration: const InputDecoration(
              labelText: 'Conta',
              border: OutlineInputBorder(),
              helperText:
                  'DEMO usa a conta DOT (saldo virtual). REAL opera com '
                  'dinheiro de verdade - comece sempre pela DEMO.',
            ),
            items: const [
              DropdownMenuItem(
                  value: BotConfig.accountDemo, child: Text('DEMO (recomendado)')),
              DropdownMenuItem(
                  value: BotConfig.accountReal,
                  child: Text('REAL (dinheiro de verdade)',
                      style: TextStyle(color: Colors.redAccent))),
            ],
            onChanged: (v) async {
              final chosen = v ?? BotConfig.accountDemo;
              if (chosen == BotConfig.accountReal) {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Usar conta REAL?'),
                    content: const Text(
                        'O bot vai operar com dinheiro de verdade e voce pode '
                        'perder tudo que apostar. Tem certeza?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Sim, usar REAL')),
                    ],
                  ),
                );
                if (confirm != true) return;
              }
              setState(() => _accountType = chosen);
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _symbol,
            decoration: const InputDecoration(
                labelText: 'Simbolo', border: OutlineInputBorder()),
            items: _symbols.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _symbol = v ?? 'R_100'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _stake,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Stake (USD)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'Duracao (ticks)', border: OutlineInputBorder()),
                  child: DropdownButton<int>(
                    value: _duration,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: [1, 2, 3, 5, 7, 10]
                        .map((d) => DropdownMenuItem(value: d, child: Text('$d')))
                        .toList(),
                    onChanged: (v) => setState(() => _duration = v ?? 5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sensibilidade da IA',
                      style: Theme.of(context).textTheme.titleSmall),
                  Slider(
                    value: _threshold,
                    min: 0.55,
                    max: 0.80,
                    divisions: 25,
                    label: '${(_threshold * 100).toStringAsFixed(0)}%',
                    onChanged: (v) => setState(() => _threshold = v),
                  ),
                  const Text(
                    'Maior = menos operacoes, mais exigente com o sinal do modelo.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Martingale'),
            subtitle: const Text('Aumenta o stake apos perdas (MAIS RISCO)'),
            value: _martingale,
            onChanged: (v) => setState(() => _martingale = v),
          ),
          if (_martingale)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Niveis maximos:'),
                  Expanded(
                    child: Slider(
                      value: _martingaleLevels.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: '$_martingaleLevels',
                      onChanged: (v) =>
                          setState(() => _martingaleLevels = v.round()),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _maxLoss,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Stop Loss diario (USD)',
                      border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _takeProfit,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Take Profit (USD)', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _maxTrades,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Maximo de operacoes', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Salvar configuracoes'),
            onPressed: () {
              final state = context.read<BotState>();
              state.saveConfig(BotConfig(
                token: _token.text.trim(),
                appId: _appId.text.trim(),
                symbol: _symbol,
                accountType: _accountType,
                baseStake: double.tryParse(_stake.text) ?? 1.0,
                durationTicks: _duration,
                entryThreshold: _threshold,
                maxDailyLoss: double.tryParse(_maxLoss.text) ?? 25.0,
                takeProfit: double.tryParse(_takeProfit.text) ?? 50.0,
                useMartingale: _martingale,
                martingaleFactor: 2.0,
                martingaleMaxLevels: _martingaleLevels,
                maxTrades: int.tryParse(_maxTrades.text) ?? 100,
              ));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Configuracoes salvas!')));
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
