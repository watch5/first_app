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
    HapticFeedback.lightImpact();
    setState(() {
      _targetMonth = DateTime(_targetMonth.year, _targetMonth.month + offset, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final thisMonthTrans = widget.transactions.where((t) => t.date.year == _targetMonth.year && t.date.month == _targetMonth.month).toList();

    int totalIncome = 0;   // 売上高
    int variableCosts = 0; // 変動費
    int fixedCosts = 0;    // 固定費
    int totalExpense = 0;  // 費用合計
    
    // 全科目で初期化
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

    // 集計ロジック (貸借逆のパターンも考慮)
    for (var t in thisMonthTrans) {
      final debit = widget.accounts.firstWhere((a) => a.id == t.debitAccountId, orElse: () => const Account(id: -1, name: '不明', type: '', costType: 'variable'));
      final credit = widget.accounts.firstWhere((a) => a.id == t.creditAccountId, orElse: () => const Account(id: -1, name: '不明', type: '', costType: 'variable'));

      // 1. 借方 (左側) の処理
      if (debit.type == 'expense') {
        totalExpense += t.amount;
        expenseBreakdownAccount[debit] = (expenseBreakdownAccount[debit] ?? 0) + t.amount;
        expenseMap[debit.name] = (expenseMap[debit.name] ?? 0) + t.amount;
        
        if (debit.costType == 'fixed') fixedCosts += t.amount;
        else variableCosts += t.amount;

      } else if (debit.type == 'income') {
        totalIncome -= t.amount;
        incomeMap[debit.name] = (incomeMap[debit.name] ?? 0) - t.amount;
      }

      // 2. 貸方 (右側) の処理
      if (credit.type == 'expense') {
        totalExpense -= t.amount;
        expenseBreakdownAccount[credit] = (expenseBreakdownAccount[credit] ?? 0) - t.amount;
        expenseMap[credit.name] = (expenseMap[credit.name] ?? 0) - t.amount;

        if (credit.costType == 'fixed') fixedCosts -= t.amount;
        else variableCosts -= t.amount;

      } else if (credit.type == 'income') {
        totalIncome += t.amount;
        incomeMap[credit.name] = (incomeMap[credit.name] ?? 0) + t.amount;
      }
    }

    // --- 経営分析ロジック ---
    final marginalProfit = totalIncome - variableCosts; // 限界利益
    final profit = marginalProfit - fixedCosts; // 利益
    
    double marginalProfitRatio = 0; // 限界利益率
    if (totalIncome > 0) {
      marginalProfitRatio = marginalProfit / totalIncome;
    }

    int breakEvenPoint = 0; // 損益分岐点
    if (marginalProfitRatio > 0) {
      breakEvenPoint = (fixedCosts / marginalProfitRatio).round();
    }

    final fmt = NumberFormat("#,###");

    // T字勘定用リスト作成
    final expenseList = expenseMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final incomeList = incomeMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    int grandTotal = 0;
    if (profit >= 0) {
      expenseList.add(MapEntry('当期純利益', profit));
      grandTotal = totalIncome;
    } else {
      incomeList.add(MapEntry('当期純損失', -profit));
      grandTotal = totalExpense;
    }
    if (grandTotal <= 0) {
       grandTotal = (totalIncome > totalExpense ? totalIncome : totalExpense);
       if (grandTotal <= 0) grandTotal = 0;
    }

    final sortedExpenses = expenseBreakdownAccount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 色の定義 (ダークモード対応)
    final positiveColor = isDark ? Colors.greenAccent[400]! : Colors.green;
    final negativeColor = isDark ? Colors.redAccent[200]! : Colors.red;
    final tealColor = isDark ? Colors.tealAccent[700]! : Colors.teal;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 月切り替え
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
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // T字勘定モード
          if (_isTableView) ...[
            TAccountTable(
              title: '損益計算書 (P/L)',
              headerColor: tealColor,
              leftItems: expenseList,
              rightItems: incomeList,
              leftTotal: grandTotal,
              rightTotal: grandTotal,
            ),
             const SizedBox(height: 10),
             if (profit >= 0)
                Text('黒字: ${fmt.format(profit)} 円', style: TextStyle(color: positiveColor, fontWeight: FontWeight.bold, fontSize: 16))
             else
                Text('赤字: ${fmt.format(-profit)} 円', style: TextStyle(color: negativeColor, fontWeight: FontWeight.bold, fontSize: 16)),

          ] else ...[
            // サマリー＆分析カード
            Card(
              elevation: 2,
              color: colorScheme.surfaceContainer, 
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildAnalysisRow('売上高', totalIncome, Colors.blueAccent),
                    const Divider(height: 20),
                    _buildAnalysisRow('変動費', variableCosts, Colors.orangeAccent),
                    _buildAnalysisRow('限界利益', marginalProfit, tealColor, isBold: true),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('限界利益率: ${(marginalProfitRatio * 100).toStringAsFixed(1)}%', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant))
                    ),
                    const Divider(height: 20),
                    _buildAnalysisRow('固定費', fixedCosts, Colors.redAccent),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        // ★修正: withOpacity -> withValues
                        color: profit >= 0 ? positiveColor.withValues(alpha: 0.1) : negativeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8)
                      ),
                      child: _buildAnalysisRow('営業利益', profit, profit >= 0 ? positiveColor : negativeColor, isBold: true, size: 20),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            
            // 損益分岐点カード
            if (breakEvenPoint > 0 && breakEvenPoint < 100000000)
              Card(
                elevation: 0,
                // ★修正: withOpacity -> withValues
                color: colorScheme.secondaryContainer.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16), 
                  // ★修正: withOpacity -> withValues
                  side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.2))
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                       Row(
                        children: [
                          Icon(Icons.balance, size: 20, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('損益分岐点 (目標売上)', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('${fmt.format(breakEvenPoint)} 円', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                      const SizedBox(height: 4),
                      Text(
                        totalIncome >= breakEvenPoint 
                        ? 'クリアしています！ (達成率 ${(totalIncome/breakEvenPoint*100).toStringAsFixed(0)}%)' 
                        : 'あと ${fmt.format(breakEvenPoint - totalIncome)} 円で黒字化ラインです',
                        style: TextStyle(
                          fontSize: 12, 
                          color: totalIncome >= breakEvenPoint ? positiveColor : Colors.orangeAccent
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 20),
            
            // グラフ
            if (totalIncome > 0 || totalExpense > 0)
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: (totalIncome > totalExpense ? totalIncome : totalExpense).toDouble() * 1.2 + 100,
                    barTouchData: BarTouchData(enabled: false),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    barGroups: [
                      BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: totalIncome.toDouble(), color: Colors.greenAccent, width: 30, borderRadius: BorderRadius.circular(4))]),
                      BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: totalExpense.toDouble(), color: Colors.redAccent, width: 30, borderRadius: BorderRadius.circular(4))]),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            
            Align(alignment: Alignment.centerLeft, child: Text('予算と実績', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface))),
            const SizedBox(height: 10),
            
            // 予算リスト
            ...sortedExpenses.map((e) {
              final account = e.key;
              final amount = e.value;
              final budget = account.monthlyBudget ?? 0;
              double progress = 0;
              if (budget > 0 && amount > 0) progress = (amount / budget).clamp(0.0, 1.0);
              if (amount < 0) progress = 0;

              return Card(
                elevation: 0,
                // ★修正: withOpacity -> withValues
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3), // 薄い背景
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            account.costType == 'fixed' ? Icons.lock_clock : Icons.shopping_bag,
                            size: 20, 
                            color: account.costType == 'fixed' ? Colors.redAccent : Colors.orangeAccent
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(account.name, style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface))),
                          Text('${fmt.format(amount)} 円', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                        ],
                      ),
                      if (budget > 0) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: progress,
                          backgroundColor: colorScheme.outlineVariant, 
                          color: amount > budget ? colorScheme.error : colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('予算: ${fmt.format(budget)}', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                            const SizedBox(width: 10),
                            Text(
                              amount > budget ? 'オーバー' : '残: ${fmt.format(budget - amount)}', 
                              style: TextStyle(fontSize: 12, color: amount > budget ? colorScheme.error : colorScheme.primary)
                            ),
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

  Widget _buildAnalysisRow(String title, int amount, Color color, {bool isBold = false, double size = 16}) {
    final fmt = NumberFormat("#,###");
    final textColor = Theme.of(context).colorScheme.onSurface;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(color: textColor, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: size)),
        Text('${fmt.format(amount)} 円', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: size)),
      ],
    );
  }
}