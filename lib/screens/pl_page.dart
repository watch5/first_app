import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../database.dart'; // フォルダ移動したのでパス修正済み
import '../../widgets/t_account_table.dart'; // フォルダ移動したのでパス修正済み

class PLPage extends StatefulWidget {
  final List<Transaction> transactions;
  final List<Account> accounts;
  const PLPage({super.key, required this.transactions, required this.accounts});

  @override
  State<PLPage> createState() => _PLPageState();
}

class _PLPageState extends State<PLPage> {
  DateTime _targetMonth = DateTime.now();
  bool _isTableView = false; 

  void _changeMonth(int offset) {
    HapticFeedback.lightImpact();
    setState(() {
      _targetMonth = DateTime(_targetMonth.year, _targetMonth.month + offset, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final thisMonthTrans = widget.transactions.where((t) => t.date.year == _targetMonth.year && t.date.month == _targetMonth.month).toList();

    int totalIncome = 0;
    int totalExpense = 0;
    
    // 全科目で初期化（0円表示用）
    Map<Account, int> expenseBreakdownAccount = {}; 
    Map<String, int> expenseMap = {}; 
    Map<String, int> incomeMap = {}; 

    for (var account in widget.accounts) {
      if (account.type == 'expense') {
        expenseBreakdownAccount[account] = 0;
        expenseMap[account.name] = 0;
      } else if (account.type == 'income') {
        incomeMap[account.name] = 0;
      }
    }

    // 集計
    for (var t in thisMonthTrans) {
      final debit = widget.accounts.firstWhere((a) => a.id == t.debitAccountId, orElse: () => const Account(id: -1, name: '不明', type: ''));
      final credit = widget.accounts.firstWhere((a) => a.id == t.creditAccountId, orElse: () => const Account(id: -1, name: '不明', type: ''));

      if (debit.type == 'expense') {
        totalExpense += t.amount;
        expenseBreakdownAccount[debit] = (expenseBreakdownAccount[debit] ?? 0) + t.amount;
        expenseMap[debit.name] = (expenseMap[debit.name] ?? 0) + t.amount;
      }
      if (credit.type == 'income') {
        totalIncome += t.amount;
        incomeMap[credit.name] = (incomeMap[credit.name] ?? 0) + t.amount;
      }
    }

    final profit = totalIncome - totalExpense;
    final fmt = NumberFormat("#,###");

    // T字勘定用のソート（金額順）
    final expenseList = expenseMap.entries.toList()..sort((a, b) {
      int compare = b.value.compareTo(a.value);
      return compare != 0 ? compare : a.key.compareTo(b.key);
    });
    final incomeList = incomeMap.entries.toList()..sort((a, b) {
      int compare = b.value.compareTo(a.value);
      return compare != 0 ? compare : a.key.compareTo(b.key);
    });

    // グラフや合計の計算
    int grandTotal = 0;
    if (profit >= 0) {
      expenseList.add(MapEntry('当期純利益', profit));
      grandTotal = totalIncome;
    } else {
      incomeList.add(MapEntry('当期純損失', -profit));
      grandTotal = totalExpense;
    }
    // どちらも0の場合の表示対策
    if (grandTotal == 0 && (totalIncome > 0 || totalExpense > 0)) {
        grandTotal = totalIncome > totalExpense ? totalIncome : totalExpense;
    }

    final colorScheme = Theme.of(context).colorScheme;

    // ★修正箇所: ここで予算リスト用のソート済みデータを作っておく（これでエラー回避！）
    final sortedExpenses = expenseBreakdownAccount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 月切り替えヘッダー
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
              Text(DateFormat('yyyy年 MM月').format(_targetMonth), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right)),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      setState(() => _isTableView = !_isTableView);
                    },
                    icon: Icon(_isTableView ? Icons.pie_chart : Icons.description),
                    tooltip: '表示切り替え',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // T字勘定（表）かグラフかの切り替え
          if (_isTableView) ...[
            TAccountTable(
              title: '損益計算書 (P/L)',
              headerColor: Colors.teal,
              leftItems: expenseList,
              rightItems: incomeList,
              leftTotal: grandTotal,
              rightTotal: grandTotal,
            ),
             const SizedBox(height: 10),
             if (profit >= 0)
                Text('黒字: ¥${fmt.format(profit)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16))
             else
                Text('赤字: ¥${fmt.format(-profit)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),

          ] else ...[
            // サマリーカード
            _buildSummaryCard('今月の純利益', profit, Colors.blue),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildSummaryCard('収益', totalIncome, Colors.green, isSmall: true)),
                const SizedBox(width: 10),
                Expanded(child: _buildSummaryCard('費用', totalExpense, Colors.red, isSmall: true)),
              ],
            ),
            const SizedBox(height: 20),
            
            // 棒グラフ（データがある場合のみ）
            if (totalIncome > 0 || totalExpense > 0)
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: (totalIncome > totalExpense ? totalIncome : totalExpense).toDouble() * 1.2 + 100,
                    barTouchData: BarTouchData(enabled: false),
                    titlesData: FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    gridData: FlGridData(show: false),
                    barGroups: [
                      BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: totalIncome.toDouble(), color: Colors.green, width: 30, borderRadius: BorderRadius.circular(4))]),
                      BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: totalExpense.toDouble(), color: Colors.red, width: 30, borderRadius: BorderRadius.circular(4))]),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            
            // 予算と実績リスト
            Align(alignment: Alignment.centerLeft, child: Text('予算と実績', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface))),
            const SizedBox(height: 10),
            
            // ★ここが修正箇所: さきほど作った sortedExpenses を使う
            ...sortedExpenses.map((e) {
              final account = e.key;
              final amount = e.value;
              final budget = account.monthlyBudget ?? 0;
              double progress = 0;
              if (budget > 0) progress = (amount / budget).clamp(0.0, 1.0);

              return Card(
                elevation: 0,
                color: colorScheme.surfaceContainer,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.shopping_bag, size: 20, color: Colors.redAccent.withValues(alpha: 0.8)),
                          const SizedBox(width: 10),
                          Expanded(child: Text(account.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                          Text('¥${fmt.format(amount)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      if (budget > 0) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.grey.withValues(alpha: 0.2),
                          color: amount > budget ? Colors.red : Colors.indigo,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('予算: ¥${fmt.format(budget)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(width: 10),
                            Text(amount > budget ? 'オーバー' : '残: ¥${fmt.format(budget - amount)}', style: TextStyle(fontSize: 12, color: amount > budget ? Colors.red : Colors.indigo)),
                          ],
                        ),
                      ]
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, int amount, Color color, {bool isSmall = false}) {
    final fmt = NumberFormat("#,###");
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('¥${fmt.format(amount)}', style: TextStyle(fontSize: isSmall ? 20 : 32, fontWeight: FontWeight.bold, color: color)),
        ]),
      ),
    );
  }
}