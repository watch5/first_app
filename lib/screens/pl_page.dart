import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database.dart'; 
import '../widgets/t_account_table.dart'; 

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
    HapticFeedback.selectionClick();
    setState(() {
      _targetMonth = DateTime(_targetMonth.year, _targetMonth.month + offset, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fmt = NumberFormat("#,###");

    // データ集計
    final thisMonthTrans = widget.transactions.where((t) => t.date.year == _targetMonth.year && t.date.month == _targetMonth.month).toList();

    int totalIncome = 0;   
    int variableCosts = 0; 
    int fixedCosts = 0;    
    int totalExpense = 0;  
    
    Map<Account, int> expenseBreakdownAccount = {}; 
    Map<String, int> expenseMap = {}; 
    Map<String, int> incomeMap = {}; 

    for (var t in thisMonthTrans) {
      final debit = widget.accounts.firstWhere((a) => a.id == t.debitAccountId, orElse: () => const Account(id: -1, name: '不明', type: '', costType: 'variable'));
      final credit = widget.accounts.firstWhere((a) => a.id == t.creditAccountId, orElse: () => const Account(id: -1, name: '不明', type: '', costType: 'variable'));

      // 借方(Expense)
      if (debit.type == 'expense') {
        totalExpense += t.amount;
        expenseBreakdownAccount[debit] = (expenseBreakdownAccount[debit] ?? 0) + t.amount;
        expenseMap[debit.name] = (expenseMap[debit.name] ?? 0) + t.amount;
        if (debit.costType == 'fixed') fixedCosts += t.amount; else variableCosts += t.amount;
      } else if (debit.type == 'income') {
        totalIncome -= t.amount;
        incomeMap[debit.name] = (incomeMap[debit.name] ?? 0) - t.amount;
      }

      // 貸方(Income)
      if (credit.type == 'expense') {
        totalExpense -= t.amount;
        expenseBreakdownAccount[credit] = (expenseBreakdownAccount[credit] ?? 0) - t.amount;
        expenseMap[credit.name] = (expenseMap[credit.name] ?? 0) - t.amount;
        if (credit.costType == 'fixed') fixedCosts -= t.amount; else variableCosts -= t.amount;
      } else if (credit.type == 'income') {
        totalIncome += t.amount;
        incomeMap[credit.name] = (incomeMap[credit.name] ?? 0) + t.amount;
      }
    }

    final profit = totalIncome - totalExpense;
    final profitMargin = totalIncome > 0 ? (profit / totalIncome * 100) : 0.0;
    
    // T字勘定用データ
    final expenseList = expenseMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final incomeList = incomeMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    int grandTotal = totalIncome > totalExpense ? totalIncome : totalExpense;
    if (profit >= 0) expenseList.add(MapEntry('当期純利益', profit));
    else incomeList.add(MapEntry('当期純損失', -profit));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            title: Text('${DateFormat('yyyy年 MM月').format(_targetMonth)} の経営成績'),
            actions: [
              IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
              IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right)),
              IconButton(
                onPressed: () => setState(() => _isTableView = !_isTableView),
                icon: Icon(_isTableView ? Icons.pie_chart : Icons.description),
                tooltip: '表示切り替え',
              ),
            ],
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              if (_isTableView) 
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TAccountTable(
                    title: '損益計算書 (P/L)',
                    headerColor: Colors.teal,
                    leftItems: expenseList,
                    rightItems: incomeList,
                    leftTotal: grandTotal,
                    rightTotal: grandTotal,
                  ),
                )
              else 
                Column(
                  children: [
                    // 1. メイン指標カード
                    _buildMainMetricCard(context, profit, profitMargin, totalIncome, isDark),
                    
                    // 2. 損益グラフ (Waterfall like BarChart)
                    Container(
                      height: 220,
                      padding: const EdgeInsets.all(16),
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: (totalIncome > 0 ? totalIncome : 10000).toDouble() * 1.1,
                          barTouchData: BarTouchData(
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipColor: (_) => Colors.blueGrey,
                            ),
                          ),
                          titlesData: FlTitlesData(
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  switch (value.toInt()) {
                                    case 0: return const Text('売上', style: TextStyle(fontSize: 10));
                                    case 1: return const Text('費用', style: TextStyle(fontSize: 10));
                                    case 2: return const Text('利益', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold));
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          barGroups: [
                            _buildBarGroup(0, totalIncome.toDouble(), Colors.blueAccent),
                            _buildBarGroup(1, totalExpense.toDouble(), Colors.redAccent),
                            _buildBarGroup(2, profit.toDouble(), profit >= 0 ? Colors.green : Colors.red),
                          ],
                        ),
                      ),
                    ),

                    // 3. 経営分析レポート
                    _buildAnalysisCard(context, profitMargin, fixedCosts, variableCosts, totalIncome, fmt, isDark),

                    // 4. 科目別内訳
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Align(alignment: Alignment.centerLeft, child: Text('費用内訳', style: TextStyle(color: colorScheme.secondary, fontWeight: FontWeight.bold))),
                    ),
                    ...expenseBreakdownAccount.entries.map((e) {
                      if (e.value <= 0) return const SizedBox.shrink();
                      final ratio = totalExpense > 0 ? (e.value / totalExpense) : 0.0;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          e.key.costType == 'fixed' ? Icons.lock : Icons.shopping_bag_outlined,
                          color: e.key.costType == 'fixed' ? Colors.redAccent : Colors.orange,
                          size: 20,
                        ),
                        title: Text(e.key.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${(ratio * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(width: 8),
                            Text('¥${fmt.format(e.value)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        subtitle: LinearProgressIndicator(
                          value: ratio,
                          backgroundColor: Colors.grey.withOpacity(0.1),
                          color: e.key.costType == 'fixed' ? Colors.redAccent.withOpacity(0.5) : Colors.orange.withOpacity(0.5),
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }),
                    const SizedBox(height: 40),
                  ],
                ),
            ]),
          ),
        ],
      ),
    );
  }

  BarChartGroupData _buildBarGroup(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y < 0 ? 0 : y, // 簡易的にマイナスは0表示（赤字は色で表現済み）
          color: color,
          width: 30,
          borderRadius: BorderRadius.circular(4),
          backDrawRodData: BackgroundBarChartRodData(show: true, toY: y, color: color.withOpacity(0.1)),
        ),
      ],
    );
  }

  Widget _buildMainMetricCard(BuildContext context, int profit, double margin, int income, bool isDark) {
    final colorScheme = Theme.of(context).colorScheme;
    final fmt = NumberFormat("#,###");
    final isProfitable = profit >= 0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isProfitable 
            ? [Colors.teal.shade700, Colors.teal.shade400] 
            : [Colors.red.shade700, Colors.red.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: (isProfitable ? Colors.teal : Colors.red).withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          Text('当期純利益 (Net Income)', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            '¥ ${fmt.format(profit)}',
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricItem('売上高', '¥${fmt.format(income)}', Colors.white),
              Container(width: 1, height: 30, color: Colors.white30),
              _buildMetricItem('利益率', '${margin.toStringAsFixed(1)}%', Colors.white),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: color.withOpacity(0.8), fontSize: 11)),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildAnalysisCard(BuildContext context, double margin, int fixed, int variable, int income, NumberFormat fmt, bool isDark) {
    // 簡易的な経営診断コメント
    String comment = "データ不足です";
    Color badgeColor = Colors.grey;
    String badgeText = "-";

    if (income > 0) {
      if (margin > 30) {
        comment = "素晴らしい高収益体質です！\nこの調子で資産を増やしましょう。";
        badgeColor = Colors.amber;
        badgeText = "Sランク: 超優良";
      } else if (margin > 10) {
        comment = "健全な黒字経営です。\n固定費の見直しでさらなる利益を！";
        badgeColor = Colors.blue;
        badgeText = "Aランク: 優良";
      } else if (margin > 0) {
        comment = "黒字ですが利益率は低めです。\n無駄遣いを減らしましょう。";
        badgeColor = Colors.green;
        badgeText = "Bランク: 普通";
      } else {
        comment = "赤字状態です緊急事態！\n固定費が高すぎる可能性があります。";
        badgeColor = Colors.red;
        badgeText = "Cランク: 注意";
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined),
                const SizedBox(width: 8),
                const Text("AI経営分析", style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(8)),
                  child: Text(badgeText, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(comment, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('固定費: ¥${fmt.format(fixed)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text('変動費: ¥${fmt.format(variable)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}