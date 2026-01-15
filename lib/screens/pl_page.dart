import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart'; // Gemini
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
  // ★ここにAPIキーを入れてください
  final String _apiKey = 'AIzaSyAjn7KgHXI8tx6lHGgmNiD7EsaaxTGWaXA';

  DateTime _targetMonth = DateTime.now();
  bool _isTableView = false; 
  
  // AI分析用
  String? _aiComment;
  bool _isAiLoading = false;
  DateTime? _lastAnalyzedMonth;

  void _changeMonth(int offset) {
    HapticFeedback.selectionClick();
    setState(() {
      _targetMonth = DateTime(_targetMonth.year, _targetMonth.month + offset, 1);
      // 月が変わったらAIコメントをリセット（ボタンを押させるため）
      if (_lastAnalyzedMonth != _targetMonth) {
        _aiComment = null;
      }
    });
  }

  // ★GeminiでP/L分析
  Future<void> _analyzeWithGemini(int income, int expense, int fixed, int variable, int profit) async {
    setState(() => _isAiLoading = true);

    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey);
      final prompt = """
        あなたはプロのファイナンシャルプランナー兼、優しい家計簿アドバイザーです。
        以下の1ヶ月の家計簿データ（損益計算書）を見て、ユーザーに短く的確なアドバイスや励ましのコメントをください。

        【データ】
        - 対象月: ${DateFormat('yyyy年M月').format(_targetMonth)}
        - 収入: $income 円
        - 支出合計: $expense 円
          - 固定費: $fixed 円
          - 変動費: $variable 円
        - 損益（利益）: $profit 円

        【ルール】
        - 日本語で140文字以内。
        - 感情豊かに、絵文字を使ってください。
        - 黒字なら褒めて、赤字なら改善点を優しく指摘してください。
        - 具体的な数字（「固定費が高めです」など）に触れてください。
      """;

      final response = await model.generateContent([Content.text(prompt)]);
      
      if (mounted) {
        setState(() {
          _aiComment = response.text;
          _lastAnalyzedMonth = _targetMonth;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _aiComment = "分析中にエラーが発生しました...😢\n($e)");
      }
    } finally {
      if (mounted) {
        setState(() => _isAiLoading = false);
      }
    }
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

      if (debit.type == 'expense') {
        totalExpense += t.amount;
        expenseBreakdownAccount[debit] = (expenseBreakdownAccount[debit] ?? 0) + t.amount;
        expenseMap[debit.name] = (expenseMap[debit.name] ?? 0) + t.amount;
        if (debit.costType == 'fixed') fixedCosts += t.amount; else variableCosts += t.amount;
      } else if (debit.type == 'income') {
        totalIncome -= t.amount;
        incomeMap[debit.name] = (incomeMap[debit.name] ?? 0) - t.amount;
      }

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
    
    // T字勘定用
    final expenseList = expenseMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final incomeList = incomeMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    int grandTotal = totalIncome > totalExpense ? totalIncome : totalExpense;
    if (profit >= 0) expenseList.add(MapEntry('当期純利益', profit));
    else incomeList.add(MapEntry('当期純損失', -profit));

    // 内訳リスト
    final sortedExpenses = expenseBreakdownAccount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final fixedList = sortedExpenses.where((e) => e.key.costType == 'fixed').toList();
    final variableList = sortedExpenses.where((e) => e.key.costType != 'fixed').toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text('${DateFormat('M月').format(_targetMonth)}の経営成績'),
            actions: [
              IconButton.filledTonal(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
              const SizedBox(width: 8),
              IconButton.filledTonal(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right)),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: () => setState(() => _isTableView = !_isTableView),
                icon: Icon(_isTableView ? Icons.pie_chart : Icons.table_chart),
              ),
              const SizedBox(width: 16),
            ],
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              if (_isTableView) 
                Padding(
                  padding: const EdgeInsets.all(16.0),
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    children: [
                      _buildMainMetricCard(context, profit, profitMargin, totalIncome, isDark),
                      const SizedBox(height: 16),

                      // ★AI分析カード
                      _buildAiAnalysisCard(context, totalIncome, totalExpense, fixedCosts, variableCosts, profit),
                      const SizedBox(height: 16),

                      // 損益グラフ
                      Card(
                        elevation: 0,
                        color: colorScheme.surfaceContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('収支のバランス', style: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 20),
                              SizedBox(
                                height: 200,
                                child: BarChart(
                                  BarChartData(
                                    alignment: BarChartAlignment.spaceAround,
                                    maxY: (totalIncome > totalExpense ? totalIncome : totalExpense).toDouble() * 1.2,
                                    barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(getTooltipColor: (_) => Colors.blueGrey)),
                                    titlesData: FlTitlesData(
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          getTitlesWidget: (value, meta) {
                                            const style = TextStyle(fontSize: 12, fontWeight: FontWeight.bold);
                                            switch (value.toInt()) {
                                              case 0: return const Padding(padding: EdgeInsets.only(top: 8), child: Text('売上', style: style));
                                              case 1: return const Padding(padding: EdgeInsets.only(top: 8), child: Text('費用', style: style));
                                              case 2: return const Padding(padding: EdgeInsets.only(top: 8), child: Text('利益', style: style));
                                            }
                                            return const SizedBox.shrink();
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
                                      _buildBarGroup(2, profit.toDouble(), profit >= 0 ? Colors.teal : Colors.red),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Divider(),
                              const SizedBox(height: 10),
                              _buildAnalysisRow(context, '固定費', fixedCosts, totalExpense, Colors.orange),
                              const SizedBox(height: 10),
                              _buildAnalysisRow(context, '変動費', variableCosts, totalExpense, Colors.blue),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      if (fixedList.isNotEmpty) ...[
                        _buildSectionHeader(context, '固定費の内訳', Icons.lock_clock),
                        ...fixedList.map((e) => _buildExpenseTile(context, e, totalExpense, fmt)),
                        const SizedBox(height: 16),
                      ],
                      
                      if (variableList.isNotEmpty) ...[
                        _buildSectionHeader(context, '変動費の内訳', Icons.shopping_cart),
                        ...variableList.map((e) => _buildExpenseTile(context, e, totalExpense, fmt)),
                        const SizedBox(height: 16),
                      ],

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  // --- AI分析カードWidget ---
  Widget _buildAiAnalysisCard(BuildContext context, int income, int expense, int fixed, int variable, int profit) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // まだデータがない場合
    if (income == 0 && expense == 0) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shadowColor: Colors.orange.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.orange.withOpacity(0.5))),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.orange),
                const SizedBox(width: 8),
                Text("AI専属アドバイザー", style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                const Spacer(),
                if (_aiComment == null && !_isAiLoading)
                  FilledButton.icon(
                    onPressed: () => _analyzeWithGemini(income, expense, fixed, variable, profit),
                    icon: const Icon(Icons.analytics, size: 16),
                    label: const Text("分析する"),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isAiLoading)
              const Center(child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(color: Colors.orange),
              ))
            else if (_aiComment != null)
              AnimatedOpacity(
                opacity: 1.0,
                duration: const Duration(milliseconds: 500),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _aiComment!,
                    style: TextStyle(fontSize: 14, height: 1.5, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              Text("今月の収支データをAIが分析し、\nアドバイスを作成します。", style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  // --- 以下は既存のUIパーツ ---
  
  BarChartGroupData _buildBarGroup(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y < 0 ? 0 : y,
          color: color,
          width: 40,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          backDrawRodData: BackgroundBarChartRodData(show: true, toY: y, color: color.withOpacity(0.1)),
        ),
      ],
    );
  }

  Widget _buildMainMetricCard(BuildContext context, int profit, double margin, int income, bool isDark) {
    final fmt = NumberFormat("#,###");
    final isProfitable = profit >= 0;

    return Container(
      width: double.infinity,
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
          BoxShadow(color: (isProfitable ? Colors.teal : Colors.red).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          Text('当期純利益', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            '¥ ${fmt.format(profit)}',
            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 1.0),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildMetricItem('売上高', '¥${fmt.format(income)}'),
              Container(width: 1, height: 30, color: Colors.white24),
              _buildMetricItem('利益率', '${margin.toStringAsFixed(1)}%'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildAnalysisRow(BuildContext context, String label, int amount, int total, Color color) {
    final fmt = NumberFormat("#,###");
    final ratio = total > 0 ? amount / total : 0.0;
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const Spacer(),
        Text('¥${fmt.format(amount)}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        SizedBox(
          width: 50,
          child: Text('(${ (ratio * 100).toStringAsFixed(1) }%)', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildExpenseTile(BuildContext context, MapEntry<Account, int> entry, int totalExpense, NumberFormat fmt) {
    final ratio = totalExpense > 0 ? (entry.value / totalExpense) : 0.0;
    final colorScheme = Theme.of(context).colorScheme;
    
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: entry.key.costType == 'fixed' ? Colors.orange.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            entry.key.costType == 'fixed' ? Icons.home_work_outlined : Icons.shopping_bag_outlined,
            color: entry.key.costType == 'fixed' ? Colors.orange : Colors.blue,
            size: 20,
          ),
        ),
        title: Text(entry.key.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: entry.key.costType == 'fixed' ? Colors.orangeAccent : Colors.blueAccent,
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('¥${fmt.format(entry.value)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text('${(ratio * 100).toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}