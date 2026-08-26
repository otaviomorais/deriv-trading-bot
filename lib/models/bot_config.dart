class BotConfig {
  static const String accountDemo = 'demo';
  static const String accountReal = 'real';

  final String token;
  final String appId;
  final String symbol;

  /// 'demo' (padrao, seguro) ou 'real'.
  final String accountType;
  final double baseStake;
  final int durationTicks;
  final double entryThreshold;
  final double maxDailyLoss;
  final double takeProfit;
  final bool useMartingale;
  final double martingaleFactor;
  final int martingaleMaxLevels;
  final int maxTrades;

  const BotConfig({
    required this.token,
    this.appId = '33wAcoYXHpsPdruTW0b7C',
    required this.symbol,
    this.accountType = accountDemo,
    this.baseStake = 1.0,
    this.durationTicks = 5,
    this.entryThreshold = 0.62,
    this.maxDailyLoss = 25.0,
    this.takeProfit = 50.0,
    this.useMartingale = false,
    this.martingaleFactor = 2.0,
    this.martingaleMaxLevels = 3,
    this.maxTrades = 100,
  });

  BotConfig copyWith({
    String? token,
    String? appId,
    String? accountType,
    String? symbol,
    double? baseStake,
    int? durationTicks,
    double? entryThreshold,
    double? maxDailyLoss,
    double? takeProfit,
    bool? useMartingale,
    double? martingaleFactor,
    int? martingaleMaxLevels,
    int? maxTrades,
  }) {
    return BotConfig(
      token: token ?? this.token,
      appId: appId ?? this.appId,
      accountType: accountType ?? this.accountType,
      symbol: symbol ?? this.symbol,
      baseStake: baseStake ?? this.baseStake,
      durationTicks: durationTicks ?? this.durationTicks,
      entryThreshold: entryThreshold ?? this.entryThreshold,
      maxDailyLoss: maxDailyLoss ?? this.maxDailyLoss,
      takeProfit: takeProfit ?? this.takeProfit,
      useMartingale: useMartingale ?? this.useMartingale,
      martingaleFactor: martingaleFactor ?? this.martingaleFactor,
      martingaleMaxLevels: martingaleMaxLevels ?? this.martingaleMaxLevels,
      maxTrades: maxTrades ?? this.maxTrades,
    );
  }
}
