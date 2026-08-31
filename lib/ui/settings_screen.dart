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
  late final TextEditingController _cooldown;

  late String _symbol;
  late String _accountType;
  late double _threshold;
  late int _duration;
  late bool _martingale;
  late int _martingaleLevels;
  late bool _paper;

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
    _cooldown = TextEditingController(text: cfg.cooldownTicks.toString());
    _symbol = cfg.symbol;
    _accountType = cfg.accountType;
    _threshold = cfg.entryThreshold;
    _duration = cfg.durationTicks;
    _martingale = cfg.useMartingale;
    _martingaleLevels = cfg.martingaleMaxLevels;
    _paper = cfg.paperTrading;
  }

  @override
  void dispose() {
    _token.dispose();
    _appId.dispose();
    _stake.dispose();
    _maxLoss.dispose();
    _takeProfit.dispose();
    _maxTrades.dispose();
    _cooldown.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _save() {
    final state = context.read<BotState>();
    final stake = double.tryParse(_stake.text.trim().replaceAll(',', '.'));
    final maxLoss = double.tryParse(_maxLoss.text.trim().replaceAll(',', '.'));
    final takeProfit =
        double.tryParse(_takeProfit.text.trim().replaceAll(',', '.'));
    final maxTrades = int.tryParse(_maxTrades.text.trim());
    final cooldown = int.tryParse(_cooldown.text.trim());

    if (stake == null || stake <= 0) {
      _showError('Stake deve ser um numero maior que zero.');
      return;
    }
    if (stake > 5000) {
      _showError('Stake acima de 5000 USD parece invalido.');
      return;
    }
    if (maxLoss == null || maxLoss <= 0) {
      _showError('Stop Loss diario deve ser maior que zero.');
      return;
    }
    if (takeProfit == null || takeProfit <= 0) {
      _showError('Take Profit deve ser maior que zero.');
      return;
    }
    if (maxTrades == null || maxTrades < 1) {
      _showError('Maximo de operacoes deve ser >= 1.');
      return;
    }
    if (cooldown == null || cooldown < 0) {
      _showError('Cooldown deve ser >= 0 ticks.');
      return;
    }

    state.saveConfig(BotConfig(
      token: _token.text.trim(),
      appId: _appId.text.trim(),
      symbol: _symbol,
      accountType: _accountType,
      baseStake: stake,
      durationTicks: _duration,
      entryThreshold: _threshold,
      maxDailyLoss: maxLoss,
      takeProfit: takeProfit,
      useMartingale: _martingale,
      martingaleFactor: 2.0,
      martingaleMaxLevels: _martingaleLevels,
      maxTrades: maxTrades,
      paperTrading: _paper,
      cooldownTicks: cooldown,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Configuracoes salvas!')));
      Navigator.pop(context);
    }
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
          SwitchListTile(
            title: const Text('Modo simulacao (paper trading)'),
            subtitle: const Text(
                'Simula contratos e resultados SEM movimentar dinheiro. '
                'Use para testar a estrategia antes da conta REAL.'),
            value: _paper,
            onChanged: (v) => setState(() => _paper = v),
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 12),
          TextField(
            controller: _cooldown,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Cooldown entre operacoes (ticks)',
                border: OutlineInputBorder(),
                helperText: 'Espera N ticks apos fechar uma operacao antes de abrir outra.'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Salvar configuracoes'),
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}