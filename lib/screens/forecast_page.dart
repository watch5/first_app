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
    // ※今回は「今日以降の取引」を取得します
    final futureTxs = await widget.db.getFutureTransactions(today, endDate);
    
    // 3. 日別予算（ユーザーが設定した目標）
    final budgets = await widget.db.getDailyBudgets(today, endDate);

    // データ構築
    List<ForecastItem> items = [];
    int runningBalance = currentBalance;

    for (int i = 0; i < _forecastDays; i++) {
      final date = today.add(Duration(days: i));
      
      // この日の固定収支 (Transactionsテーブルにある予定)
      // ※未来の日付で登録されたTransactionを「確定済みの予定」として扱います
      int income = 0;
      int fixedExpense = 0;
      
      // 勘定科目情報を取得していないので、簡易的に「資産が増えたら収入、減ったら支出」とみなします
      // 本来はAccountテーブルとJOINすべきですが、ロジック簡略化のため
      // Transactionの「借方が資産ならプラス、貸方が資産ならマイナス」として計算します
      // ※厳密には getFutureTransactions で計算済み情報を取得するのがベストですが
      // ここでは簡易的に全Txを回します（件数が少ない前提）
      final daysTxs = futureTxs.where((t) => 
        t.date.year == date.year && t.date.month == date.month && t.date.day == date.day
      );
      
      // 資産IDリストが必要ですが、ここでは簡易ロジックとして
      // 「アプリ内のTransactionデータはすべて資産変動を伴う」前提で、
      // 資金繰り表としては「入力済みの予定＝変動」とします。
      // ※より正確にするには、ここでdebit/creditのAccountTypeをチェックしてください。
      // 今回は「入力された未来の取引はすべてキャッシュフローに影響する」として計算します。
      // （家計簿アプリでは通常、未来日付で入力するのは家賃や給料など重要項目だけなので）
      
      // 簡易計算: 
      // 借方IDが資産かどうか判定するのが重いので、
      // 「未来日付のデータがある場合、それを『予定』として表示する」ことに注力します。
      
      // 日別予算を取得
      final budgetObj = budgets.firstWhere(
        (b) => b.date.year == date.year && b.date.month == date.month && b.date.day == date.day,
        orElse: () => DailyBudget(date: date, amount: 2000), // デフォルト予算 2000円
      );
      
      // 残高シミュレーション
      // 残高 = 前日残高 + (予定収入 - 予定支出) - 日別予算(生活費)
      
      // 注: ここではシンプルに「予定データ」の合計を計算したいですが、
      // 厳密な資産増減判定が難しいので、
      // ★「未来のデータは、金額が大きい場合（1万円以上）を表示する」などの簡易ロジックにします
      
      int scheduledChange = 0; // 予定による増減
      // ここは本来DB側で計算すべきですが、今回は「日別予算」が主役なので、
      // Transactionは「別途加算」せず、純粋に「予算を引いていく」グラフにします。
      // もしユーザーが「給料」を未来入力していたら、それを反映させるロジックが必要です。
      // 今回は【バージョンアップ版】として、以下のロジックにします。
      
      // 「未来のTransaction」は、まだ入力されていないことが多いので、
      // 基本は「日別予算」分だけ毎日減っていくグラフを描きます。
      // そこにユーザーが手動でTransactionを入れたら反映される仕組みです。
      
      // 修正: 確実に計算するために、accountsを取得します
      final allAccounts = await widget.db.getAllAccounts();
      final assetIds = allAccounts.where((a) => a.type == 'asset').map((a) => a.id).toList();

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

    return Scaffold(
      body: Column(
        children: [
          // 1. グラフエリア (上部)
          Container(
            height: 250,
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 10),
            color: colorScheme.surfaceContainer,
            child: Column(
              children: [
                Text('向こう30日の資金繰り予測', style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Expanded(
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (touchedSpots) {
                            return touchedSpots.map((spot) {
                              return LineTooltipItem(
                                '${NumberFormat("#,###").format(spot.y)}円',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              );
                            }).toList();
                          },
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _items.asMap().entries.map((e) {
                            return FlSpot(e.key.toDouble(), e.value.balance.toDouble());
                          }).toList(),
                          isCurved: true,
                          color: colorScheme.primary,
                          barWidth: 3,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true, 
                            color: colorScheme.primary.withOpacity(0.1)
                          ),
                        ),
                        // ゼロライン（危険ライン）
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
                  title: Row(
                    children: [
                      SizedBox(
                        width: 80, 
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
                                  ? '+${fmt.format(item.scheduledChange)} (収入予定)' 
                                  : '${fmt.format(item.scheduledChange)} (支払予定)',
                                style: TextStyle(
                                  fontSize: 12, 
                                  color: item.scheduledChange > 0 ? Colors.green : Colors.red
                                )
                              ),
                            Text('残高予測: ${fmt.format(item.balance)}', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.outlineVariant)
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('予算', style: TextStyle(fontSize: 10)),
                        Text('¥${fmt.format(item.budget)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  onTap: () => _editBudget(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

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