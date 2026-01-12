import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database.dart';

class BudgetPage extends StatefulWidget {
  final List<Transaction> transactions;
  final List<Account> accounts;
  final VoidCallback onDataChanged; // ★追加: 親画面を更新するためのコールバック

  const BudgetPage({
    super.key, 
    required this.transactions, 
    required this.accounts,
    required this.onDataChanged, // ★追加
  });

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  DateTime _currentMonth = DateTime.now();
  int _globalMonthlyBudget = 0;

  @override
  void initState() {
    super.initState();
    _loadGlobalBudget();
  }

  Future<void> _loadGlobalBudget() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _globalMonthlyBudget = prefs.getInt('global_monthly_budget') ?? 0;
    });
  }

  Future<void> _setGlobalBudget(int amount) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('global_monthly_budget', amount);
    _loadGlobalBudget();
    // 全体予算はSharedPreferences管理なので画面全体の再描画は必須ではないが、念のため呼んでおく
    widget.onDataChanged(); 
  }

  Future<void> _showEditGlobalBudgetDialog(BuildContext context) async {
    final controller = TextEditingController(text: _globalMonthlyBudget == 0 ? '' : _globalMonthlyBudget.toString());
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('今月の全体予算を設定'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '予算金額 (円)',
            hintText: '例: 100000',
            suffixText: '円',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(controller.text) ?? 0;
              _setGlobalBudget(val);
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditCategoryBudgetDialog(BuildContext context, Account account) async {
    final controller = TextEditingController(text: account.budget == 0 ? '' : account.budget.toString());
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${account.name}の予算設定'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '月間予算 (円)',
                hintText: '例: 30000',
                suffixText: '円',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 10),
            const Text('0にすると「予算なし」になります', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          FilledButton(
            onPressed: () async {
              final val = int.tryParse(controller.text) ?? 0;
              await MyDatabase().updateAccountBudget(account.id, val);
              if (mounted) Navigator.pop(ctx, true); 
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ).then((result) {
      if (result == true) {
         // ★修正: 親画面のデータを再読み込みさせる
         widget.onDataChanged();
         
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('予算を更新しました')),
         );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fmt = NumberFormat("#,###");

    // 今月のデータを抽出
    final monthStart = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final monthEnd = DateTime(_currentMonth.year, _currentMonth.month + 1, 0, 23, 59, 59);
    final daysInMonth = monthEnd.day;
    final todayDay = DateTime.now().day;
    
    int remainingDays = daysInMonth - todayDay + 1;
    if (remainingDays < 1) remainingDays = 1;

    final monthlyTxs = widget.transactions.where((t) {
      return t.date.isAfter(monthStart.subtract(const Duration(seconds: 1))) && 
             t.date.isBefore(monthEnd.add(const Duration(seconds: 1)));
    }).toList();

    // 科目ごとの集計
    Map<int, int> expenseMap = {};
    int totalExpense = 0;
    
    for (var t in monthlyTxs) {
      final debit = widget.accounts.firstWhere((a) => a.id == t.debitAccountId, orElse: () => const Account(id: -1, name: '不明', type: '', costType: ''));
      final credit = widget.accounts.firstWhere((a) => a.id == t.creditAccountId, orElse: () => const Account(id: -1, name: '不明', type: '', costType: ''));

      if (debit.type == 'expense') {
        expenseMap[debit.id] = (expenseMap[debit.id] ?? 0) + t.amount;
        totalExpense += t.amount;
      }
      if (credit.type == 'expense') {
        expenseMap[credit.id] = (expenseMap[credit.id] ?? 0) - t.amount;
        totalExpense -= t.amount;
      }
    }

    int remainingGlobalBudget = _globalMonthlyBudget - totalExpense;
    int dailyBudget = remainingGlobalBudget > 0 ? (remainingGlobalBudget ~/ remainingDays) : 0;

    final sortedEntries = expenseMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        title: Text('${DateFormat('M月').format(_currentMonth)}の予算'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() {
              _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
            }),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => setState(() {
              _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          // 全体予算カード
          Card(
            margin: const EdgeInsets.all(16),
            color: colorScheme.surfaceContainerHighest,
            child: InkWell(
              onTap: () => _showEditGlobalBudgetDialog(context),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('全体の月予算', style: TextStyle(fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            Text(
                              _globalMonthlyBudget == 0 ? '未設定' : '¥${fmt.format(_globalMonthlyBudget)}',
                              style: TextStyle(
                                fontSize: 18, 
                                color: _globalMonthlyBudget == 0 ? Colors.grey : colorScheme.primary
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.edit, size: 16, color: Colors.grey),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _globalMonthlyBudget == 0 ? 0 : (totalExpense / _globalMonthlyBudget).clamp(0.0, 1.0),
                      backgroundColor: Colors.white,
                      color: (totalExpense > _globalMonthlyBudget && _globalMonthlyBudget > 0) ? Colors.red : colorScheme.primary,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('実績: ¥${fmt.format(totalExpense)}'),
                        Text(
                          '残り: ¥${fmt.format(remainingGlobalBudget)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: remainingGlobalBudget < 0 ? Colors.red : Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.today, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          _globalMonthlyBudget == 0 
                            ? '予算を設定すると日割り計算できます' 
                            : '今日使える目安: ¥${fmt.format(dailyBudget)}',
                          style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.secondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('科目別予算', style: TextStyle(fontSize: 14, color: Colors.grey)),
            ),
          ),

          // 科目別リスト
          Expanded(
            child: ListView.builder(
              itemCount: widget.accounts.where((a) => a.type == 'expense').length,
              itemBuilder: (context, index) {
                final expenseAccounts = widget.accounts.where((a) => a.type == 'expense').toList();
                final account = expenseAccounts[index];
                final amount = expenseMap[account.id] ?? 0;
                final budget = account.budget;
                
                double progress = 0.0;
                if (budget > 0) {
                  progress = (amount / budget).clamp(0.0, 1.0);
                }

                return ListTile(
                  onTap: () => _showEditCategoryBudgetDialog(context, account),
                  leading: CircleAvatar(
                    backgroundColor: colorScheme.secondaryContainer,
                    child: Text(account.name.substring(0, 1), style: TextStyle(color: colorScheme.onSecondaryContainer)),
                  ),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(account.name),
                      if (budget > 0)
                        Text(
                          '残り ¥${fmt.format(budget - amount)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: (amount > budget) ? Colors.red : Colors.green,
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      if (budget > 0)
                        LinearProgressIndicator(
                          value: progress,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          color: (amount > budget) ? Colors.red : colorScheme.primary,
                        )
                      else
                        Text('予算未設定 (タップして設定)', style: TextStyle(fontSize: 10, color: colorScheme.outline)),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('¥${fmt.format(amount)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            budget > 0 ? '/ ¥${fmt.format(budget)}' : '',
                            style: TextStyle(color: colorScheme.outline),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.edit, size: 16, color: Colors.grey),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}