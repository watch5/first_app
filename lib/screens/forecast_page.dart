import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database.dart';

class ForecastPage extends StatefulWidget {
  final MyDatabase db;
  const ForecastPage({super.key, required this.db});

  @override
  State<ForecastPage> createState() => _ForecastPageState();
}

class _ForecastPageState extends State<ForecastPage> {
  // 30日分を表示
  final int _forecastDays = 30;
  List<ForecastItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadForecast();
  }

  Future<void> _loadForecast() async {
    setState(() => _isLoading = true);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDate = today.add(Duration(days: _forecastDays));

    // 1. 現在の資産総額（スタート地点）
    int currentBalance = await widget.db.getCurrentAssetBalance();

    // 2. 未来の取引（家賃や給料など、すでに入力済みの予定）
    final futureTxs = await widget.db.getFutureTransactions(today, endDate);
    
    // 3. 日別予算（ユーザーが設定した目標）
    final budgets = await widget.db.getDailyBudgets(today, endDate);

    // データ構築
    List<ForecastItem> items = [];
    int runningBalance = currentBalance;
    final allAccounts = await widget.db.getAllAccounts();
    final assetIds = allAccounts.where((a) => a.type == 'asset').map((a) => a.id).toList();

    for (int i = 0; i < _forecastDays; i++) {
      final date = today.add(Duration(days: i));
      
      final daysTxs = futureTxs.where((t) => 
        t.date.year == date.year && t.date.month == date.month && t.date.day == date.day
      );
      
      final budgetObj = budgets.firstWhere(
        (b) => b.date.year == date.year && b.date.month == date.month && b.date.day == date.day,
        orElse: () => DailyBudget(date: date, amount: 2000), // デフォルト予算 2000円
      );
      
      int scheduledChange = 0; // 予定による増減

      for (var tx in daysTxs) {
        if (assetIds.contains(tx.debitAccountId)) scheduledChange += tx.amount; // 資産増
        if (assetIds.contains(tx.creditAccountId)) scheduledChange -= tx.amount; // 資産減
      }

      runningBalance += scheduledChange;
      runningBalance -= budgetObj.amount; // 予算分（食費など）を使うと仮定して減らす

      items.add(ForecastItem(
        date: date,
        budget: budgetObj.amount,
        balance: runningBalance,
        scheduledChange: scheduledChange,
      ));
    }

    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  Future<void> _editBudget(ForecastItem item) async {
    final controller = TextEditingController(text: item.budget.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${DateFormat('M/d').format(item.date)} の予算設定'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             const Text('この日に使う予定の金額（食費・日用品など）を入力してください'),
             const SizedBox(height: 10),
             TextField(
               controller: controller,
               keyboardType: TextInputType.number,
               autofocus: true,
               decoration: const InputDecoration(suffixText: '円'),
             ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result != null) {
      await widget.db.setDailyBudget(item.date, result);
      _loadForecast(); // 再計算
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // グラフの最小・最大値を計算して、見栄えを調整
    double minBalance = _items.map((e) => e.balance.toDouble()).reduce((a, b) => a < b ? a : b);
    double maxBalance = _items.map((e) => e.balance.toDouble()).reduce((a, b) => a > b ? a : b);
    // 少し余裕を持たせる
    if (minBalance > 0) minBalance = 0; // 0円スタートを含める
    double intervalY = (maxBalance - minBalance) / 4; 
    if (intervalY <= 0) intervalY = 10000;

    return Scaffold(
      body: Column(
        children: [
          // 1. グラフエリア (上部)
          Container(
            height: 320, // 高さを広げてリッチに
            padding: const EdgeInsets.fromLTRB(10, 40, 20, 10),
            color: colorScheme.surfaceContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 10),
                  child: Text('向こう30日の資金繰り予測', style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: LineChart(
                    LineChartData(
                      // --- グリッド線 ---
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        horizontalInterval: intervalY,
                        verticalInterval: 1, // インデックスベース
                        getDrawingHorizontalLine: (value) {
                          return FlLine(color: colorScheme.outlineVariant.withOpacity(0.5), strokeWidth: 1, dashArray: [5, 5]);
                        },
                        getDrawingVerticalLine: (value) {
                          // 5日ごとに縦線
                          if (value.toInt() % 5 == 0) {
                            return FlLine(color: colorScheme.outlineVariant.withOpacity(0.5), strokeWidth: 1);
                          }
                          return const FlLine(color: Colors.transparent);
                        },
                      ),
                      
                      // --- 軸ラベル (日付・金額) ---
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        
                        // 下部 (日付)
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            interval: 5, // 5日おきに表示
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index >= 0 && index < _items.length) {
                                final date = _items[index].date;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    DateFormat('M/d').format(date),
                                    style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        
                        // 左側 (金額)
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40, // 金額表示用の幅
                            interval: intervalY,
                            getTitlesWidget: (value, meta) {
                              if (value == 0) return const SizedBox.shrink(); // 0は被るので消す
                              // 万単位などで短縮表示
                              final valInt = value.toInt();
                              String text;
                              if (valInt.abs() >= 10000) {
                                text = '${(valInt / 10000).toStringAsFixed(0)}万';
                              } else {
                                text = '${valInt ~/ 1000}k';
                              }
                              return Text(text, style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant), textAlign: TextAlign.right);
                            },
                          ),
                        ),
                      ),
                      
                      borderData: FlBorderData(show: false),
                      
                      // --- タッチ操作 (ツールチップ) ---
                      lineTouchData: LineTouchData(
                        handleBuiltInTouches: true,
                        touchTooltipData: LineTouchTooltipData(
                          // 吹き出しの色
                          getTooltipColor: (touchedSpot) => colorScheme.inverseSurface.withOpacity(0.9),
                          // 角丸設定の行を削除しました（デフォルト値を利用）
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((spot) {
                              final index = spot.x.toInt();
                              if (index < 0 || index >= _items.length) return null;
                              final item = _items[index];
                              
                              return LineTooltipItem(
                                '${DateFormat('MM/dd').format(item.date)}\n',
                                TextStyle(color: colorScheme.onInverseSurface, fontWeight: FontWeight.bold, fontSize: 12),
                                children: [
                                  TextSpan(
                                    text: '${NumberFormat("#,###").format(item.balance)} 円',
                                    // ★修正箇所: primaryFixedAccent -> inversePrimary
                                    style: TextStyle(color: colorScheme.inversePrimary, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ]
                              );
                            }).toList();
                          },
                        ),
                      ),
                      
                      // --- 線のデータ ---
                      lineBarsData: [
                        LineChartBarData(
                          spots: _items.asMap().entries.map((e) {
                            return FlSpot(e.key.toDouble(), e.value.balance.toDouble());
                          }).toList(),
                          isCurved: true, // 滑らかに
                          color: colorScheme.primary,
                          barWidth: 3,
                          isStrokeCapRound: true,
                          
                          // ドット (データ点)
                          dotData: FlDotData(
                            show: true,
                            checkToShowDot: (spot, barData) {
                              // 最初と最後だけドットを表示
                              return spot.x == 0 || spot.x == _items.length - 1;
                            },
                          ),
                          
                          // 塗りつぶし (グラデーション)
                          belowBarData: BarAreaData(
                            show: true, 
                            gradient: LinearGradient(
                              colors: [
                                colorScheme.primary.withOpacity(0.3),
                                colorScheme.primary.withOpacity(0.0),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                        // ゼロライン（赤線、危険ライン）
                        LineChartBarData(
                          spots: [const FlSpot(0, 0), FlSpot((_items.length - 1).toDouble(), 0)],
                          color: Colors.red.withOpacity(0.5),
                          barWidth: 1,
                          dashArray: [5, 5],
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 2. リストエリア (下部)
          Expanded(
            child: ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _items[index];
                final isWeekend = item.date.weekday == 6 || item.date.weekday == 7;
                final dateStr = DateFormat('M/d (E)', 'ja').format(item.date);
                final fmt = NumberFormat("#,###");
                
                // 危険フラグ（残高マイナス）
                final isDanger = item.balance < 0;

                return ListTile(
                  tileColor: isDanger ? colorScheme.errorContainer.withOpacity(0.1) : null,
                  dense: true, // 少しコンパクトに
                  title: Row(
                    children: [
                      SizedBox(
                        width: 70, 
                        child: Text(
                          dateStr, 
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isWeekend ? Colors.redAccent : colorScheme.onSurface
                          )
                        )
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.scheduledChange != 0)
                              Text(
                                item.scheduledChange > 0 
                                  ? '+${fmt.format(item.scheduledChange)} (収入)' 
                                  : '${fmt.format(item.scheduledChange)} (支払)',
                                style: TextStyle(
                                  fontSize: 11, 
                                  color: item.scheduledChange > 0 ? Colors.green : Colors.red
                                )
                              ),
                            Text('${fmt.format(item.balance)}円', style: TextStyle(fontWeight: FontWeight.bold, color: isDanger ? colorScheme.error : colorScheme.onSurface)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  trailing: InkWell(
                    onTap: () => _editBudget(item),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('日予算', style: TextStyle(fontSize: 8)),
                          Text('¥${fmt.format(item.budget)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ★クラス定義を忘れずに追加
class ForecastItem {
  final DateTime date;
  final int budget;
  final int balance;
  final int scheduledChange; // その日の固定変動（家賃引き落とし等）

  ForecastItem({
    required this.date,
    required this.budget,
    required this.balance,
    required this.scheduledChange,
  });
}