import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart'; // ★広告用
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // おまじない
  await initializeDateFormatting();
  await MobileAds.instance.initialize(); // ★広告システムの起動
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
    await HapticFeedback.heavyImpact();
    await _db.deleteTransaction(id);
    await _loadData();
  }

  void _openSettings() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('科目の管理'),
            onTap: () async {
              Navigator.pop(ctx);
              await Navigator.of(context).push(MaterialPageRoute(builder: (context) => AccountSettingsPage(db: _db)));
              _loadData();
            },
          ),
          ListTile(
            leading: const Icon(Icons.bookmark),
            title: const Text('テンプレートの管理'),
            subtitle: const Text('よく使う取引（家賃など）を登録'),
            onTap: () async {
              Navigator.pop(ctx);
              await Navigator.of(context).push(MaterialPageRoute(builder: (context) => TemplateSettingsPage(db: _db)));
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
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
      appBar: AppBar(
        title: const Text('Dualy'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings),
        ],
      ),
      // ★変更: 画面の下に広告を入れるため、Columnで囲む
      body: Column(
        children: [
          Expanded(child: screens[_selectedIndex]), // メインコンテンツ
          const AdBanner(), // ★ここに広告バナーを配置！
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          HapticFeedback.selectionClick();
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list_alt), label: '明細'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: '損益(P/L)'),
          NavigationDestination(icon: Icon(Icons.account_balance), label: '資産(B/S)'),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () async {
                HapticFeedback.mediumImpact();
                if (_accounts.isEmpty) return;
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => AddTransactionPage(accounts: _accounts, db: _db)),
                );
                if (result != null) {
                  await _addTransaction(
                    result['debitId'], 
                    result['creditId'], 
                    result['amount'],
                    result['date'],
                  );
                  HapticFeedback.heavyImpact();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('記帳しました！')));
                  }
                }
              },
              icon: const Icon(Icons.edit),
              label: const Text('記帳'),
            )
          : null,
    );
  }
}

// --- ★新規追加: 広告バナー用ウィジェット ---
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  // テスト用ID (リリース時は本物に書き換えます)
  final String _adUnitId = 'ca-app-pub-3940256099942544/6300978111';

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    _bannerAd = BannerAd(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bannerAd != null && _isLoaded) {
      return Container(
        alignment: Alignment.center,
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      );
    }
    // 読み込み中は何も表示しない（高さを確保しても良い）
    return const SizedBox.shrink();
  }
}

// --- 1. 明細リスト画面 (そのまま) ---
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
      accounts.firstWhere((a) => a.id == id, orElse: () => const Account(id: -1, name: '?', type: '', monthlyBudget: null)).name;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) return const Center(child: Text('データがありません'));
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final t = transactions[index];
        final debitName = _getAccountName(t.debitAccountId);
        final creditName = _getAccountName(t.creditAccountId);
        final fmt = NumberFormat("#,###");

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
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_back, size: 16, color: Colors.grey),
                ),
                Text(creditName, style: const TextStyle(color: Colors.grey)),
              ],
            ),
            subtitle: Text(DateFormat('yyyy/MM/dd').format(t.date)),
            trailing: Text(
              fmt.format(t.amount),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
            ),
            onLongPress: () {
               HapticFeedback.heavyImpact();
               onDelete(t.id);
            },
          ),
        );
      },
    );
  }
}

// --- 2. 損益計算書 (P/L) (そのまま) ---
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
    Map<Account, int> expenseBreakdownAccount = {}; 
    Map<String, int> expenseMap = {}; 
    Map<String, int> incomeMap = {}; 

    for (var t in thisMonthTrans) {
      final debit = widget.accounts.firstWhere((a) => a.id == t.debitAccountId);
      final credit = widget.accounts.firstWhere((a) => a.id == t.creditAccountId);

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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
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
                Text('黒字: ¥${fmt.format(profit)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
             else
                Text('赤字: ¥${fmt.format(-profit)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),

          ] else ...[
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
            const Align(alignment: Alignment.centerLeft, child: Text('予算と実績', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            const SizedBox(height: 10),
            ...expenseBreakdownAccount.entries.map((e) {
              final account = e.key;
              final amount = e.value;
              final budget = account.monthlyBudget ?? 0;
              double progress = 0;
              if (budget > 0) progress = (amount / budget).clamp(0.0, 1.0);

              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2))),
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

// --- 3. 貸借対照表 (B/S) (そのまま) ---
class BSPage extends StatefulWidget {
  final List<Transaction> transactions;
  final List<Account> accounts;
  const BSPage({super.key, required this.transactions, required this.accounts});

  @override
  State<BSPage> createState() => _BSPageState();
}

class _BSPageState extends State<BSPage> {
  DateTime _targetDate = DateTime.now();
  bool _isTableView = false; 

  @override
  Widget build(BuildContext context) {
    int totalAsset = 0;
    int totalLiability = 0;
    Map<String, int> assetMap = {};
    Map<String, int> liabilityMap = {};

    final endOfTargetDate = DateTime(_targetDate.year, _targetDate.month, _targetDate.day).add(const Duration(days: 1));

    for (var a in widget.accounts) {
      if (a.type != 'asset' && a.type != 'liability') continue;
      int balance = 0;
      for (var t in widget.transactions) {
        if (t.date.isBefore(endOfTargetDate)) {
          if (t.debitAccountId == a.id) balance += t.amount;
          if (t.creditAccountId == a.id) balance -= t.amount;
        }
      }
      if (balance != 0) {
        if (a.type == 'asset') {
          totalAsset += balance;
          assetMap[a.name] = balance;
        } else if (a.type == 'liability') {
          totalLiability += balance;
          liabilityMap[a.name] = balance;
        }
      }
    }

    final netAssets = totalAsset - totalLiability;
    final fmt = NumberFormat("#,###");

    final assetList = assetMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final liabilityList = liabilityMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    liabilityList.add(MapEntry('純資産', netAssets));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () async {
                  HapticFeedback.lightImpact();
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
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                  child: Row(
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
              const SizedBox(width: 12),
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
          const SizedBox(height: 20),

          if (_isTableView) ...[
            TAccountTable(
              title: '貸借対照表 (B/S)',
              headerColor: Colors.indigo,
              leftItems: assetList,
              rightItems: liabilityList,
              leftTotal: totalAsset,
              rightTotal: totalAsset,
            ),
          ] else ...[
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
                Text('¥${fmt.format(netAssets)}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
              ]),
            ),
            const SizedBox(height: 30),
            if (totalAsset > 0)
              SizedBox(
                height: 200,
                child: PieChart(PieChartData(
                  sections: assetMap.entries.map((e) {
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
            ...assetMap.entries.map((e) {
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
            }),
          ],
        ],
      ),
    );
  }
}

// --- 4. 入力画面 (そのまま) ---
class AddTransactionPage extends StatefulWidget {
  final List<Account> accounts;
  final MyDatabase db;
  const AddTransactionPage({super.key, required this.accounts, required this.db});

  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  final _amountController = TextEditingController();
  int? _debitId;
  int? _creditId;
  DateTime _selectedDate = DateTime.now();

  void _showTemplates() async {
    HapticFeedback.lightImpact();
    final templates = await widget.db.getAllTemplates();
    if (!mounted) return;

    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('テンプレートがありません。設定から登録してください。')));
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('よく使う取引を選択', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: templates.length,
                itemBuilder: (context, index) {
                  final t = templates[index];
                  final debitName = widget.accounts.firstWhere((a) => a.id == t.debitAccountId, orElse: () => const Account(id: -1, name: '?', type: '')).name;
                  final creditName = widget.accounts.firstWhere((a) => a.id == t.creditAccountId, orElse: () => const Account(id: -1, name: '?', type: '')).name;
                  
                  return ListTile(
                    leading: const Icon(Icons.bookmark, color: Colors.indigo),
                    title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('$debitName ← $creditName'),
                    trailing: Text('¥${NumberFormat("#,###").format(t.amount)}'),
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      setState(() {
                        _debitId = t.debitAccountId;
                        _creditId = t.creditAccountId;
                        _amountController.text = t.amount.toString();
                      });
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t.name} をセットしました')));
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('記帳'),
        actions: [
           TextButton.icon(
             onPressed: _showTemplates,
             icon: const Icon(Icons.bookmark_outline),
             label: const Text('よく使う'),
           ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            GestureDetector(
              onTap: () async {
                HapticFeedback.lightImpact();
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
                  HapticFeedback.mediumImpact();
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

// --- 5. 科目設定画面 (そのまま) ---
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

  void _addAccountDialog() {
    final nameController = TextEditingController();
    final budgetController = TextEditingController();
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
                HapticFeedback.mediumImpact();
                final budget = int.tryParse(budgetController.text);
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
            subtitle: a.monthlyBudget != null ? Text('月予算: ¥${fmt.format(a.monthlyBudget)}') : Text(a.type),
          );
        },
      ),
    );
  }
}

// --- 6. 共通部品 (TAccountTable) (そのまま) ---
class TAccountTable extends StatelessWidget {
  final String title;
  final Color headerColor;
  final List<MapEntry<String, int>> leftItems;
  final List<MapEntry<String, int>> rightItems;
  final int leftTotal;
  final int rightTotal;

  const TAccountTable({
    super.key,
    required this.title,
    required this.headerColor,
    required this.leftItems,
    required this.rightItems,
    required this.leftTotal,
    required this.rightTotal,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat("#,###");
    final borderColor = Theme.of(context).colorScheme.outline;

    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildColumn(context, leftItems, leftTotal, true)),
                VerticalDivider(width: 1, thickness: 1, color: borderColor),
                Expanded(child: _buildColumn(context, rightItems, rightTotal, false)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColumn(BuildContext context, List<MapEntry<String, int>> items, int total, bool isLeft) {
    final fmt = NumberFormat("#,###");
    return Column(
      children: [
        ...items.map((e) {
          final isSummary = e.key == '純資産' || e.key == '当期純利益' || e.key == '当期純損失';
          final textColor = isSummary ? Colors.indigo : null;
          
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(e.key, style: TextStyle(fontSize: 12, fontWeight: isSummary ? FontWeight.bold : FontWeight.normal, color: textColor), overflow: TextOverflow.ellipsis)),
                Text(fmt.format(e.value), style: TextStyle(fontSize: 12, fontWeight: isSummary ? FontWeight.bold : FontWeight.normal, color: textColor)),
              ],
            ),
          );
        }),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.1),
            border: const Border(top: BorderSide(color: Colors.grey)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("計", style: TextStyle(fontWeight: FontWeight.bold)),
              Text(fmt.format(total), style: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
            ],
          ),
        ),
      ],
    );
  }
}

// --- 7. テンプレート設定画面 (そのまま) ---
class TemplateSettingsPage extends StatefulWidget {
  final MyDatabase db;
  const TemplateSettingsPage({super.key, required this.db});

  @override
  State<TemplateSettingsPage> createState() => _TemplateSettingsPageState();
}

class _TemplateSettingsPageState extends State<TemplateSettingsPage> {
  List<Template> _templates = [];
  List<Account> _accounts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final t = await widget.db.getAllTemplates();
    final a = await widget.db.getAllAccounts();
    setState(() {
      _templates = t;
      _accounts = a;
    });
  }

  void _addTemplateDialog() {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    int? debitId;
    int? creditId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('テンプレートの追加'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: '名前 (例: 家賃)')),
                  TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '金額')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: debitId,
                    hint: const Text('借方 (何に？)'),
                    items: _accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                    onChanged: (v) => setState(() => debitId = v),
                  ),
                  DropdownButtonFormField<int>(
                    value: creditId,
                    hint: const Text('貸方 (どうやって？)'),
                    items: _accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                    onChanged: (v) => setState(() => creditId = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
              TextButton(
                onPressed: () async {
                  final amount = int.tryParse(amountController.text);
                  if (nameController.text.isNotEmpty && amount != null && debitId != null && creditId != null) {
                    HapticFeedback.mediumImpact();
                    await widget.db.addTemplate(nameController.text, debitId!, creditId!, amount);
                    _loadData();
                    Navigator.pop(ctx);
                  }
                },
                child: const Text('追加'),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('テンプレート管理'), actions: [
        IconButton(onPressed: _addTemplateDialog, icon: const Icon(Icons.add)),
      ]),
      body: _templates.isEmpty 
        ? const Center(child: Text('テンプレートがありません\n右上の＋ボタンから追加してください', textAlign: TextAlign.center))
        : ListView.builder(
          itemCount: _templates.length,
          itemBuilder: (context, index) {
            final t = _templates[index];
            final debitName = _accounts.firstWhere((a) => a.id == t.debitAccountId, orElse: () => const Account(id: -1, name: '?', type: '')).name;
            final creditName = _accounts.firstWhere((a) => a.id == t.creditAccountId, orElse: () => const Account(id: -1, name: '?', type: '')).name;

            return ListTile(
              title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('$debitName ← $creditName / ¥${NumberFormat("#,###").format(t.amount)}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.grey),
                onPressed: () async {
                  HapticFeedback.heavyImpact();
                  await widget.db.deleteTemplate(t.id);
                  _loadData();
                },
              ),
            );
          },
        ),
    );
  }
}