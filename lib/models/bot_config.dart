class BotConfig {
  static const defaultSymbol = 'R_100';

  final String token;
  final String symbol;
  final double baseStake;
  final int durationTicks;
  final double entryThreshold;
  final double maxDailyLoss;
  final double takeProfit;
  final bool useMartingale;
  final double martingaleFactor;
  final int maxTrades;

  const BotConfig({
    required this.token,
    required this.symbol,
    this.baseStake = 1.0,
    this.durationTicks = 5,
    this.entryThreshold = 0.62,
    this.maxDailyLoss = 25.0,
    this.takeProfit = 50.0,
    this.useMartingale = false,
    this.martingaleFactor = 2.0,
    this.maxTrades = 100,
  });

  BotConfig copyWith({
    String? token,
    String? symbol,
    double? baseStake,
    int? durationTicks,
    double? entryThreshold,
    double? maxDailyLoss,
    double? takeProfit,
    bool? useMartingale,
    double? martingaleFactor,
    int? maxTrades,
  }) {
    return BotConfig(
      token: token ?? this.token,
      symbol: symbol ?? this.symbol,
      baseStake: baseStake ?? this.baseStake,
      durationTicks: durationTicks ?? this.durationTicks,
      entryThreshold: entryThreshold ?? this.entryThreshold,
      maxDailyLoss: maxDailyLoss ?? this.maxDailyLoss,
      takeProfit: takeProfit ?? this.takeProfit,
      useMartingale: useMartingale ?? this.useMartingale,
      martingaleFactor: martingaleFactor ?? this.martingaleFactor,
      maxTrades: maxTrades ?? this.maxTrades,
    );
  }
}
