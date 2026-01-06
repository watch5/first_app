import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:google_fonts/google_fonts.dart'; 
import 'screens/auth_page.dart'; // ★追加済み

import 'database.dart';

// 各画面・部品をインポート
import 'screens/transaction_list_page.dart';
import 'screens/pl_page.dart';
import 'screens/bs_page.dart';
import 'screens/add_transaction_page.dart';
import 'screens/account_settings_page.dart';
import 'screens/template_settings_page.dart';
import 'widgets/ad_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  await MobileAds.instance.initialize();
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
        textTheme: GoogleFonts.notoSansJpTextTheme(),
      ),

      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansJpTextTheme(ThemeData.dark().textTheme),
      ),

      themeMode: ThemeMode.system, 
      
      // ★ここを修正しました！
      // アプリ起動時にまず「認証画面 (AuthPage)」を表示します。
      // 認証が成功すると、AuthPageの中で MainScreen に移動する仕組みになっています。
      home: const AuthPage(), 
    );
  }
}

// ↓ MainScreenクラスなどはそのままでOKです（変更なし）
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
      // 日付の新しい順に
      _transactions = transactions.reversed.toList();
    });
  }

  Future<void> _addTransaction(int debitId, int creditId, int amount, DateTime date) async {
    await _db.addTransaction(debitId, creditId, amount, date);
    await _loadData();
  }

  Future<void> _updateTransaction(int id, int debitId, int creditId, int amount, DateTime date) async {
    await _db.updateTransaction(id, debitId, creditId, amount, date);
    await _loadData();
  }

  Future<void> _deleteTransaction(int id) async {
    await HapticFeedback.heavyImpact();
    await _db.deleteTransaction(id);
    await _loadData();
  }

  // 編集画面を開く
  void _editTransaction(Transaction t) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => AddTransactionPage(
        accounts: _accounts, 
        db: _db,
        transaction: t,
      )),
    );

    if (result != null && result.containsKey('id')) {
      await _updateTransaction(
        result['id'],
        result['debitId'],
        result['creditId'],
        result['amount'],
        result['date'],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('修正しました！')));
      }
    }
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
              _loadData(); // 科目変更を反映
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
      TransactionListScreen(
        transactions: _transactions,
        accounts: _accounts,
        onDelete: _deleteTransaction,
        onEdit: _editTransaction,
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
      body: Column(
        children: [
          Expanded(child: screens[_selectedIndex]),
          const AdBanner(), 
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
                
                if (result != null && !result.containsKey('id')) {
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