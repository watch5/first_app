import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'database.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Myリッチ家計簿',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          // 背景色だけ設定
          background: Colors.grey[50], 
        ),
        useMaterial3: true,
        // エラーの原因だった cardTheme 設定を削除しました
      ),
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

  Future<void> _addTransaction(int debitId, int creditId, int amount) async {
    await _db.addTransaction(debitId, creditId, amount, DateTime.now());
    await _loadData();
  }

  Future<void> _deleteTransaction(int id) async {
    await _db.deleteTransaction(id);
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      TransactionListPage(
        transactions: _transactions,
        accounts: _accounts,
        onDelete: _deleteTransaction,
      ),
      PLPage(transactions: _transactions, accounts: _accounts),
      BSPage(transactions: _transactions, accounts: _accounts),
    ];

    return Scaffold(
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
                  MaterialPageRoute(
                    builder: (context) => AddTransactionPage(accounts: _accounts),
                  ),
                );
                if (result != null) {
                  await _addTransaction(result['debitId'], result['creditId'], result['amount']);
                }
              },
              icon: const Icon(Icons.edit),
              label: const Text('記帳'),
            )
          : null,
    );
  }
}

// --- 1. 明細リスト画面 ---
class TransactionListPage extends StatelessWidget {
  final List<Transaction> transactions;
  final List<Account> accounts;
  final Function(int) onDelete;

  const TransactionListPage({
    super.key,
    required this.transactions,
    required this.accounts,
    required this.onDelete,
  });

  String _getAccountName(int id) => 
      accounts.firstWhere((a) => a.id == id, orElse: () => const Account(id: -1, name: '?', type: '')).name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('取引明細'), centerTitle: false),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: transactions.length,
        itemBuilder: (context, index) {
          final t = transactions[index];
          final debitName = _getAccountName(t.debitAccountId);
          final creditName = _getAccountName(t.creditAccountId);
          final fmt = NumberFormat("#,###");

          return Card(
            elevation: 0, // 個別に設定
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            color: Colors.white,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Row(
                children: [
                  Text(debitName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_back, size: 16, color: Colors.grey),
                  ),
                  Text(creditName, style: const TextStyle(color: Colors.grey)),
                ],
              ),
              subtitle: Text(DateFormat('yyyy/MM/dd').format(t.date)),
              trailing: Text(
                '¥${fmt.format(t.amount)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
              ),
              onLongPress: () => onDelete(t.id),
            ),
          );
        },
      ),
    );
  }
}

// --- 2. 損益計算書 (P/L) 画面 ---
class PLPage extends StatelessWidget {
  final List<Transaction> transactions;
  final List<Account> accounts;

  const PLPage({super.key, required this.transactions, required this.accounts});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final thisMonthTrans = transactions.where((t) => t.date.month == now.month && t.date.year == now.year).toList();

    int totalIncome = 0;
    int totalExpense = 0;
    Map<String, int> expenseBreakdown = {};

    for (var t in thisMonthTrans) {
      final debit = accounts.firstWhere((a) => a.id == t.debitAccountId);
      final credit = accounts.firstWhere((a) => a.id == t.creditAccountId);

      if (debit.type == 'expense') {
        totalExpense += t.amount;
        expenseBreakdown[debit.name] = (expenseBreakdown[debit.name] ?? 0) + t.amount;
      }
      if (credit.type == 'income') {
        totalIncome += t.amount;
      }
    }

    final profit = totalIncome - totalExpense;
    final fmt = NumberFormat("#,###");

    return Scaffold(
      appBar: AppBar(title: const Text('今月の損益 (P/L)'), centerTitle: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSummaryCard('純利益', profit, Colors.blue),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildSummaryCard('収益', totalIncome, Colors.green, isSmall: true)),
                const SizedBox(width: 10),
                Expanded(child: _buildSummaryCard('費用', totalExpense, Colors.red, isSmall: true)),
              ],
            ),
            const SizedBox(height: 20),
            
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (totalIncome > totalExpense ? totalIncome : totalExpense).toDouble() * 1.2 + 100, // +100で余白確保
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const Text('収益');
                          if (value == 1) return const Text('費用');
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
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
            
            const Align(alignment: Alignment.centerLeft, child: Text('費用の内訳', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            const SizedBox(height: 10),
            ...expenseBreakdown.entries.map((e) {
              return Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.redAccent, child: Icon(Icons.shopping_bag, color: Colors.white, size: 20)),
                  title: Text(e.key),
                  trailing: Text('¥${fmt.format(e.value)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, int amount, Color color, {bool isSmall = false}) {
    final fmt = NumberFormat("#,###");
    return Card(
      elevation: 0,
      color: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('¥${fmt.format(amount)}', style: TextStyle(fontSize: isSmall ? 20 : 32, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

// --- 3. 貸借対照表 (B/S) 画面 ---
class BSPage extends StatelessWidget {
  final List<Transaction> transactions;
  final List<Account> accounts;

  const BSPage({super.key, required this.transactions, required this.accounts});

  @override
  Widget build(BuildContext context) {
    int totalAsset = 0;
    Map<String, int> assetBreakdown = {};

    for (var a in accounts.where((a) => a.type == 'asset')) {
      int balance = 0;
      for (var t in transactions) {
        if (t.debitAccountId == a.id) balance += t.amount;
        if (t.creditAccountId == a.id) balance -= t.amount;
      }
      if (balance != 0) {
        totalAsset += balance;
        assetBreakdown[a.name] = balance;
      }
    }

    final fmt = NumberFormat("#,###");

    return Scaffold(
      appBar: AppBar(title: const Text('貸借対照表 (B/S)'), centerTitle: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Colors.indigo, Colors.blue]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: Column(
                children: [
                  const Text('現在の純資産', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 5),
                  Text('¥${fmt.format(totalAsset)}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 30),

            if (totalAsset > 0)
              SizedBox(
                height: 200,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                    sections: assetBreakdown.entries.map((e) {
                      final isLarge = e.value / totalAsset > 0.5;
                      return PieChartSectionData(
                        color: Colors.primaries[e.key.hashCode % Colors.primaries.length],
                        value: e.value.toDouble(),
                        title: '${(e.value / totalAsset * 100).toStringAsFixed(0)}%',
                        radius: isLarge ? 60 : 50,
                        titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      );
                    }).toList(),
                  ),
                ),
              ),
            const SizedBox(height: 20),

            const Align(alignment: Alignment.centerLeft, child: Text('資産の内訳', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            const SizedBox(height: 10),
            ...assetBreakdown.entries.map((e) {
              return Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
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
      ),
    );
  }
}

// --- 入力画面 ---
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('記帳'), backgroundColor: Colors.white, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.indigo),
              decoration: const InputDecoration(
                hintText: '¥0',
                border: InputBorder.none,
              ),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  elevation: 5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  final amount = int.tryParse(_amountController.text);
                  if (amount != null && _debitId != null && _creditId != null) {
                    Navigator.of(context).pop({'debitId': _debitId, 'creditId': _creditId, 'amount': amount});
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
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
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