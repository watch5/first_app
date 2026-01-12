import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ★追加
import '../database.dart';

class ForecastPage extends StatefulWidget {
  final MyDatabase db;
  const ForecastPage({super.key, required this.db});

  @override
  State<ForecastPage> createState() => _ForecastPageState();
}

class _ForecastPageState extends State<ForecastPage> {
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

    // ★追加: 予算タブで設定した「全体の月予算」を取得
    final prefs = await SharedPreferences.getInstance();
    final globalMonthlyBudget = prefs.getInt('global_monthly_budget') ?? 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDate = today.add(Duration(days: _forecastDays));

    int currentBalance = await widget.db.getCurrentAssetBalance();
    final futureTxs = await widget.db.getFutureTransactions(today, endDate);
    final budgets = await widget.db.getDailyBudgets(today, endDate);
    final recurringList = await widget.db.getAllRecurringTransactions();

    // 負債残高の計算
    final allTxs = await widget.db.getTransactions();
    final allAccounts = await widget.db.getAllAccounts();
    Map<int, int> liabilityBalances = {};
    
    for (var account in allAccounts.where((a) => a.type == 'liability')) {
      int bal = 0;
      for (var t in allTxs) {
        if (t.creditAccountId == account.id) bal += t.amount;
        if (t.debitAccountId == account.id) bal -= t.amount;
      }
      liabilityBalances[account.id] = bal;
    }

    List<ForecastItem> items = [];
    int runningBalance = currentBalance;
    final assetIds = allAccounts.where((a) => a.type == 'asset').map((a) => a.id).toList();

    for (int i = 0; i < _forecastDays; i++) {
      final date = today.add(Duration(days: i));
      
      final daysTxs = futureTxs.where((t) => t.date.year == date.year && t.date.month == date.month && t.date.day == date.day);
      final daysRecurring = recurringList.where((r) => r.dayOfMonth == date.day);

      int scheduledChange = 0;

      for (var tx in daysTxs) {
        if (assetIds.contains(tx.debitAccountId)) scheduledChange += tx.amount; 
        if (assetIds.contains(tx.creditAccountId)) scheduledChange -= tx.amount; 
      }
      
      for (var r in daysRecurring) {
        if (assetIds.contains(r.debitAccountId)) scheduledChange += r.amount; 
        if (assetIds.contains(r.creditAccountId)) scheduledChange -= r.amount; 
      }

      // クレカ引き落とし予測
      for (var liability in allAccounts.where((a) => a.type == 'liability' && a.withdrawalDay != null && a.paymentAccountId != null)) {
        if (date.day == liability.withdrawalDay) {
          if (assetIds.contains(liability.paymentAccountId)) {
            int amountToPay = liabilityBalances[liability.id] ?? 0;
            if (amountToPay > 0) {
              scheduledChange -= amountToPay;
            }
          }
        }
      }

      // ★修正: 予算設定ロジック
      // その月の「日割り予算」を計算（月予算 ÷ その月の日数）
      int daysInCurrentMonth = DateTime(date.year, date.month + 1, 0).day;
      int dailyBudgetBase = globalMonthlyBudget > 0 ? (globalMonthlyBudget ~/ daysInCurrentMonth) : 0;

      // 個別に設定した日次予算があればそれを優先、なければ日割り計算値を使う
      final budgetObj = budgets.firstWhere(
        (b) => b.date.year == date.year && b.date.month == date.month && b.date.day == date.day,
        orElse: () => DailyBudget(date: date, amount: dailyBudgetBase), 
      );

      runningBalance += scheduledChange;
      runningBalance -= budgetObj.amount;

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
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(suffixText: '円', helperText: 'この日だけの特別予算を設定できます'),
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
      _loadForecast();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_items.isEmpty) return const Scaffold(body: Center(child: Text("データがありません")));

    double minBalance = _items.map((e) => e.balance.toDouble()).reduce((a, b) => a < b ? a : b);
    double maxBalance = _items.map((e) => e.balance.toDouble()).reduce((a, b) => a > b ? a : b);
    if (minBalance > 0) minBalance = 0; 
    double intervalY = (maxBalance - minBalance) / 4; 
    if (intervalY <= 0) intervalY = 10000;

    return Scaffold(
      body: Column(
        children: [
          Container(
            height: 320, 
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
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        horizontalInterval: intervalY,
                        getDrawingHorizontalLine: (value) => FlLine(color: colorScheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1, dashArray: [5, 5]),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            interval: 5, 
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index >= 0 && index < _items.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(DateFormat('M/d').format(_items[index].date), style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            interval: intervalY,
                            getTitlesWidget: (value, meta) {
                              if (value == 0) return const SizedBox.shrink(); 
                              final val = value.toInt();
                              return Text(val.abs() >= 10000 ? '${(val / 10000).toStringAsFixed(0)}万' : '${val ~/ 1000}k', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant), textAlign: TextAlign.right);
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _items.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.balance.toDouble())).toList(),
                          isCurved: true, 
                          color: colorScheme.primary,
                          barWidth: 3,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(show: true, color: colorScheme.primary.withValues(alpha: 0.1)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _items[index];
                final dateStr = DateFormat('M/d (E)', 'ja').format(item.date);
                final fmt = NumberFormat("#,###");
                
                return ListTile(
                  tileColor: item.balance < 0 ? colorScheme.errorContainer.withValues(alpha: 0.1) : null,
                  dense: true, 
                  title: Row(
                    children: [
                      SizedBox(width: 70, child: Text(dateStr, style: TextStyle(fontWeight: FontWeight.bold, color: item.date.weekday >= 6 ? Colors.redAccent : colorScheme.onSurface))),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.scheduledChange != 0)
                              Text(
                                '${item.scheduledChange > 0 ? '+' : ''}${fmt.format(item.scheduledChange)}',
                                style: TextStyle(fontSize: 11, color: item.scheduledChange > 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)
                              ),
                            Text('${fmt.format(item.balance)}円', style: TextStyle(fontWeight: FontWeight.bold, color: item.balance < 0 ? colorScheme.error : colorScheme.onSurface)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  trailing: Text('予算: ${fmt.format(item.budget)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
  final int scheduledChange; 

  ForecastItem({required this.date, required this.budget, required this.balance, required this.scheduledChange});
}