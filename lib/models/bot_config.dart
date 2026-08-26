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

  Map<String, dynamic> toJson() => {
        'token': token,
        'appId': appId,
        'symbol': symbol,
        'accountType': accountType,
        'baseStake': baseStake,
        'durationTicks': durationTicks,
        'entryThreshold': entryThreshold,
        'maxDailyLoss': maxDailyLoss,
        'takeProfit': takeProfit,
        'useMartingale': useMartingale,
        'martingaleFactor': martingaleFactor,
        'martingaleMaxLevels': martingaleMaxLevels,
        'maxTrades': maxTrades,
      };

  factory BotConfig.fromJson(Map<String, dynamic> j) => BotConfig(
        token: j['token'] as String? ?? '',
        appId: j['appId'] as String? ?? '33wAcoYXHpsPdruTW0b7C',
        symbol: j['symbol'] as String? ?? 'R_100',
        accountType: j['accountType'] == BotConfig.accountReal
            ? BotConfig.accountReal
            : BotConfig.accountDemo,
        baseStake: (j['baseStake'] as num?)?.toDouble() ?? 1.0,
        durationTicks: j['durationTicks'] as int? ?? 5,
        entryThreshold: (j['entryThreshold'] as num?)?.toDouble() ?? 0.62,
        maxDailyLoss: (j['maxDailyLoss'] as num?)?.toDouble() ?? 25.0,
        takeProfit: (j['takeProfit'] as num?)?.toDouble() ?? 50.0,
        useMartingale: j['useMartingale'] as bool? ?? false,
        martingaleFactor: (j['martingaleFactor'] as num?)?.toDouble() ?? 2.0,
        martingaleMaxLevels: j['martingaleMaxLevels'] as int? ?? 3,
        maxTrades: j['maxTrades'] as int? ?? 100,
      );
}
