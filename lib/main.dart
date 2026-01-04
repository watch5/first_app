import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'database.dart';

Future<void> main() async {
  await initializeDateFormatting();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dualy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final MyDatabase _db = MyDatabase();
  List<Transaction> _transactions = [];
  List<Account> _accounts = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await _db.seedDefaultAccounts();
    await _loadData();
  }

  Future<void> _loadData() async {
    final accounts = await _db.getAllAccounts();
    final transactions = await _db.getTransactions();
    setState(() {
      _accounts = accounts;
      _transactions = transactions.reversed.toList();
    });
  }

  Future<void> _addTransaction(int debitId, int creditId, int amount, DateTime date) async {
    await _db.addTransaction(debitId, creditId, amount, date);
    await _loadData();
  }

  Future<void> _deleteTransaction(int id) async {
    await _db.deleteTransaction(id);
    await _loadData();
  }

  void _openAccountSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => AccountSettingsPage(db: _db)),
    );
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      TransactionListPage(transactions: _transactions, accounts: _accounts, onDelete: _deleteTransaction),
      // ★変更: データと一緒に渡す
      PLPage(transactions: _transactions, accounts: _accounts),
      BSPage(transactions: _transactions, accounts: _accounts),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dualy'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _openAccountSettings),
        ],
      ),
      body: screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list_alt), label: '明細'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: '損益(P/L)'),
          NavigationDestination(icon: Icon(Icons.account_balance), label: '資産(B/S)'),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () async {
                if (_accounts.isEmpty) return;
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => AddTransactionPage(accounts: _accounts)),
                );
                if (result != null) {
                  await _addTransaction(result['debitId'], result['creditId'], result['amount'], result['date']);
                }
              },
              icon: const Icon(Icons.edit),
              label: const Text('記帳'),
            )
          : null,
    );
  }
}

// --- 1. 明細リスト画面 (変更なし) ---
class TransactionListPage extends StatelessWidget {
  final List<Transaction> transactions;
  final List<Account> accounts;
  final Function(int) onDelete;

  const TransactionListPage({super.key, required this.transactions, required this.accounts, required this.onDelete});

  String _getAccountName(int id) => accounts.firstWhere((a) => a.id == id, orElse: () => const Account(id: -1, name: '?', type: '', monthlyBudget: null)).name;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) return const Center(child: Text('データがありません'));
    final fmt = NumberFormat("#,###");

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final t = transactions[index];
        final debitName = _getAccountName(t.debitAccountId);
        final creditName = _getAccountName(t.creditAccountId);

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Row(
              children: [
                Text(debitName, style: const TextStyle(fontWeight: FontWeight.bold)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_back, size: 16, color: Colors.grey)),
                Text(creditName, style: const TextStyle(color: Colors.grey)),
              ],
            ),
            subtitle: Text(DateFormat('yyyy/MM/dd').format(t.date)),
            trailing: Text(fmt.format(t.amount), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
            onLongPress: () => onDelete(t.id),
          ),
        );
      },
    );
  }
}

// --- 2. 損益計算書 (P/L) - 月指定 & 予算対比 ---
class PLPage extends StatefulWidget {
  final List<Transaction> transactions;
  final List<Account> accounts;
  const PLPage({super.key, required this.transactions, required this.accounts});

  @override
  State<PLPage> createState() => _PLPageState();
}

class _PLPageState extends State<PLPage> {
  DateTime _targetMonth = DateTime.now(); // ★選択中の月

  void _changeMonth(int offset) {
    setState(() {
      _targetMonth = DateTime(_targetMonth.year, _targetMonth.month + offset, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 選択された月のデータだけ抽出
    final thisMonthTrans = widget.transactions.where((t) => t.date.year == _targetMonth.year && t.date.month == _targetMonth.month).toList();

    int totalIncome = 0;
    int totalExpense = 0;
    Map<Account, int> expenseBreakdown = {};

    for (var t in thisMonthTrans) {
      final debit = widget.accounts.firstWhere((a) => a.id == t.debitAccountId);
      final credit = widget.accounts.firstWhere((a) => a.id == t.creditAccountId);

      if (debit.type == 'expense') {
        totalExpense += t.amount;
        expenseBreakdown[debit] = (expenseBreakdown[debit] ?? 0) + t.amount;
      }
      if (credit.type == 'income') totalIncome += t.amount;
    }

    final profit = totalIncome - totalExpense;
    final fmt = NumberFormat("#,###");

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ★月切り替えバー
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
              Text(DateFormat('yyyy年 MM月').format(_targetMonth), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right)),
            ],
          ),
          const SizedBox(height: 10),

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
          const Align(alignment: Alignment.centerLeft, child: Text('予算と実績', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          const SizedBox(height: 10),
          
          // ★予算対比リスト
          ...expenseBreakdown.entries.map((e) {
            final account = e.key;
            final amount = e.value;
            final budget = account.monthlyBudget ?? 0;
            double progress = 0;
            if (budget > 0) progress = (amount / budget).clamp(0.0, 1.0);

            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
              ),
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
                        color: amount > budget ? Colors.red : Colors.indigo, // 予算オーバーで赤くなる
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('予算: ¥${fmt.format(budget)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(width: 10),
                          Text(amount > budget ? 'オーバー' : '残: ¥${fmt.format(budget - amount)}', 
                               style: TextStyle(fontSize: 12, color: amount > budget ? Colors.red : Colors.indigo)),
                        ],
                      ),
                    ]
                  ],
                ),
              ),
            );
          }),
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

// --- 3. 貸借対照表 (B/S) - 日付指定 ---
class BSPage extends StatefulWidget {
  final List<Transaction> transactions;
  final List<Account> accounts;
  const BSPage({super.key, required this.transactions, required this.accounts});

  @override
  State<BSPage> createState() => _BSPageState();
}

class _BSPageState extends State<BSPage> {
  DateTime _targetDate = DateTime.now(); // ★B/Sの基準日

  @override
  Widget build(BuildContext context) {
    int totalAsset = 0;
    Map<String, int> assetBreakdown = {};

    // ★基準日以前のデータのみで集計するロジック
    // その日の終わりの時間(23:59:59)まで含めるため、翌日の0:00より前とする
    final endOfTargetDate = DateTime(_targetDate.year, _targetDate.month, _targetDate.day).add(const Duration(days: 1));

    for (var a in widget.accounts.where((a) => a.type == 'asset')) {
      int balance = 0;
      for (var t in widget.transactions) {
        if (t.date.isBefore(endOfTargetDate)) { // ★ここが日付フィルター
          if (t.debitAccountId == a.id) balance += t.amount;
          if (t.creditAccountId == a.id) balance -= t.amount;
        }
      }
      if (balance != 0) {
        totalAsset += balance;
        assetBreakdown[a.name] = balance;
      }
    }

    final fmt = NumberFormat("#,###");

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ★日付選択バー
          GestureDetector(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _targetDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (date != null) setState(() => _targetDate = date);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today, size: 20),
                  const SizedBox(width: 10),
                  Text('${DateFormat('yyyy/MM/dd').format(_targetDate)} 時点', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Colors.indigo, Colors.blue]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              const Text('純資産', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 5),
              Text('¥${fmt.format(totalAsset)}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
            ]),
          ),
          const SizedBox(height: 30),
          if (totalAsset > 0)
            SizedBox(
              height: 200,
              child: PieChart(PieChartData(
                sections: assetBreakdown.entries.map((e) {
                  return PieChartSectionData(
                    color: Colors.primaries[e.key.hashCode % Colors.primaries.length],
                    value: e.value.toDouble(),
                    title: '${(e.value / totalAsset * 100).toStringAsFixed(0)}%',
                    radius: 50,
                    titleStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  );
                }).toList(),
              )),
            ),
          const SizedBox(height: 20),
          ...assetBreakdown.entries.map((e) {
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2))),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.account_balance_wallet, color: Colors.blue),
                ),
                title: Text(e.key),
                trailing: Text('¥${fmt.format(e.value)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}

// --- 4. 入力画面 (変更なし) ---
class AddTransactionPage extends StatefulWidget {
  final List<Account> accounts;
  const AddTransactionPage({super.key, required this.accounts});

  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  final _amountController = TextEditingController();
  int? _debitId;
  int? _creditId;
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('記帳')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            GestureDetector(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (date != null) setState(() => _selectedDate = date);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20)
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today, size: 16, color: Colors.indigo),
                    const SizedBox(width: 8),
                    Text(DateFormat('yyyy/MM/dd (E)', 'ja').format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.indigo),
              decoration: const InputDecoration(hintText: '¥0', border: InputBorder.none),
            ),
            const Divider(),
            const SizedBox(height: 20),
            _buildDropdown('何に使った？ (借方)', _debitId, (val) => setState(() => _debitId = val)),
            const SizedBox(height: 20),
            _buildDropdown('どう払った？ (貸方)', _creditId, (val) => setState(() => _creditId = val)),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, elevation: 5, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: () {
                  final amount = int.tryParse(_amountController.text);
                  if (amount != null && _debitId != null && _creditId != null) {
                    Navigator.of(context).pop({'debitId': _debitId, 'creditId': _creditId, 'amount': amount, 'date': _selectedDate});
                  }
                },
                child: const Text('記帳する', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, int? value, ValueChanged<int?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              hint: const Text('選択してください'),
              items: widget.accounts.map((account) {
                return DropdownMenuItem(value: account.id, child: Text(account.name));
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

// --- 5. 科目設定画面 (予算登録対応) ---
class AccountSettingsPage extends StatefulWidget {
  final MyDatabase db;
  const AccountSettingsPage({super.key, required this.db});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  List<Account> _accounts = [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final list = await widget.db.getAllAccounts();
    setState(() => _accounts = list);
  }

  // ★ダイアログに予算入力欄を追加
  void _addAccountDialog() {
    final nameController = TextEditingController();
    final budgetController = TextEditingController(); // 予算用
    String type = 'expense';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('科目の追加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: '科目名（例：推し活）')),
            const SizedBox(height: 10),
            TextField(controller: budgetController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '月予算 (任意, 円)')),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: type,
              items: const [
                DropdownMenuItem(value: 'expense', child: Text('費用 (使ったお金)')),
                DropdownMenuItem(value: 'income', child: Text('収益 (入ってくるお金)')),
                DropdownMenuItem(value: 'asset', child: Text('資産 (現金・銀行)')),
                DropdownMenuItem(value: 'liability', child: Text('負債 (クレカ等)')),
              ],
              onChanged: (val) => type = val!,
              decoration: const InputDecoration(labelText: '種類'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                final budget = int.tryParse(budgetController.text);
                // ★予算付きで登録
                await widget.db.addAccount(nameController.text, type, budget);
                _loadAccounts();
                Navigator.pop(ctx);
              }
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat("#,###");
    return Scaffold(
      appBar: AppBar(title: const Text('科目の管理'), actions: [
        IconButton(onPressed: _addAccountDialog, icon: const Icon(Icons.add)),
      ]),
      body: ListView.builder(
        itemCount: _accounts.length,
        itemBuilder: (context, index) {
          final a = _accounts[index];
          IconData icon;
          Color color;
          switch (a.type) {
            case 'asset': icon = Icons.account_balance_wallet; color = Colors.blue; break;
            case 'income': icon = Icons.savings; color = Colors.green; break;
            case 'liability': icon = Icons.credit_card; color = Colors.orange; break;
            default: icon = Icons.shopping_bag; color = Colors.redAccent;
          }
          return ListTile(
            leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.2), child: Icon(icon, color: color, size: 20)),
            title: Text(a.name),
            // ★予算を表示
            subtitle: a.monthlyBudget != null ? Text('月予算: ¥${fmt.format(a.monthlyBudget)}') : Text(a.type),
            trailing: IconButton(
              icon: const Icon(Icons.edit, size: 16),
              onPressed: () {
                // ここに予算編集機能を追加できます（今回は割愛）
              },
            ),
          );
        },
      ),
    );
  }
}