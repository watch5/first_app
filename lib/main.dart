import 'dart:async'; // ★追加
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:google_fonts/google_fonts.dart'; 
import 'package:app_links/app_links.dart'; // ★追加

import 'database.dart';
import 'screens/auth_page.dart'; 

// 各画面・部品をインポート
import 'screens/transaction_list_page.dart';
import 'screens/pl_page.dart';
import 'screens/bs_page.dart';
import 'screens/forecast_page.dart';
import 'screens/add_transaction_page.dart';
import 'screens/account_settings_page.dart';
import 'screens/template_settings_page.dart';
import 'screens/recurring_settings_page.dart'; 
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
      
      // アプリ起動時はまず認証画面を表示
      home: const AuthPage(), 
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

  // ★Deep Link用の変数
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initData();
    _initDeepLinks(); // ★初期化
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initData() async {
    await _db.seedDefaultAccounts();
    await _db.seedDebugData();
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

  // ---------------------------------------------------------
  // ★Deep Linkの実装 (自動連携)
  // ---------------------------------------------------------
  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // リンクの監視
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  Future<void> _handleDeepLink(Uri uri) async {
    // dualy://add?amount=... のみ処理
    if (uri.host != 'add') return;

    final params = uri.queryParameters;
    final amountStr = params['amount'];
    final debitName = params['debit'];
    final creditName = params['credit'];

    if (amountStr == null || debitName == null || creditName == null) return;

    final amount = int.tryParse(amountStr);
    if (amount == null) return;

    if (_accounts.isEmpty) {
      await _loadData();
    }

    int? debitId;
    int? creditId;

    try {
      debitId = _accounts.firstWhere((a) => a.name == debitName).id;
      creditId = _accounts.firstWhere((a) => a.name == creditName).id;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('自動連携エラー: 科目「$debitName」または「$creditName」が見つかりません'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // ★重要: isAuto: true を渡して記帳
    await _addTransaction(debitId, creditId, amount, DateTime.now(), isAuto: true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.link, color: Colors.white), // アイコンをリンク用に
              const SizedBox(width: 10),
              Expanded(child: Text('自動連携: $debitName ¥$amount を記帳しました')),
            ],
          ),
          backgroundColor: Colors.teal,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // ★変更: isAuto引数を追加
  Future<void> _addTransaction(int debitId, int creditId, int amount, DateTime date, {bool isAuto = false}) async {
    await _db.addTransaction(debitId, creditId, amount, date, isAuto: isAuto);
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
              _loadData();
            },
          ),
          ListTile(
            leading: const Icon(Icons.repeat),
            title: const Text('固定費・サブスクの管理'),
            subtitle: const Text('家賃や給料日を登録して予測に反映'),
            onTap: () async {
              Navigator.pop(ctx);
              await Navigator.of(context).push(MaterialPageRoute(builder: (context) => RecurringSettingsPage(db: _db)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.bookmark),
            title: const Text('テンプレートの管理'),
            subtitle: const Text('よく使う取引（手動入力用）'),
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
    // 画面のリスト
    final List<Widget> screens = [
      TransactionListScreen(
        transactions: _transactions,
        accounts: _accounts,
        onDelete: _deleteTransaction,
        onEdit: _editTransaction,
      ),
      PLPage(transactions: _transactions, accounts: _accounts),
      
      // ★修正: BSPageに db と更新用関数を渡す
      BSPage(
        transactions: _transactions, 
        accounts: _accounts, 
        db: _db, // ★追加
        onDataChanged: () => _loadData(), // ★追加
      ),
      
      ForecastPage(db: _db), 
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
          NavigationDestination(icon: Icon(Icons.timeline), label: '資金繰り'),
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
                  // 手動入力なので isAuto はデフォルト(false)
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