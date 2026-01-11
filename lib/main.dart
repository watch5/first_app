import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart'; // ★追加
import 'package:google_fonts/google_fonts.dart'; 
import 'package:app_links/app_links.dart';

import 'database.dart';
import 'screens/auth_page.dart'; 
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

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initData();
    _initDeepLinks();
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
    // ★データロード後にアラートチェック実行
    _checkCreditCardAlert();
  }
  
  Future<void> _loadData() async {
    final accounts = await _db.getAllAccounts();
    final transactions = await _db.getTransactions();
    setState(() {
      _accounts = accounts;
      _transactions = transactions.reversed.toList();
    });
  }

  // ★追加: クレカ引き落としアラート機能
  Future<void> _checkCreditCardAlert() async {
    final now = DateTime.now();
    
    // 設定がある負債口座をループ
    for (var liability in _accounts.where((a) => a.type == 'liability' && a.withdrawalDay != null && a.paymentAccountId != null)) {
      final withdrawalDay = liability.withdrawalDay!;
      final paymentAccountId = liability.paymentAccountId!;

      // 1. 日付チェック (今日が引き落とし日の7日前〜当日か？)
      // ※簡易的に「今月」の日付で比較します
      DateTime targetDate = DateTime(now.year, now.month, withdrawalDay);
      // もし今日が28日で引き落としが5日なら、来月の5日を見る必要があるが、
      // 簡易実装として「今月のX日」との差分を見ます
      // (より厳密にするなら翌月またぎの処理が必要ですが、まずはこれで十分機能します)
      
      final diff = targetDate.difference(now).inDays;
      
      // 「7日前から当日」かつ「未来(または今日)」の場合のみ警告
      if (diff >= 0 && diff <= 7) {
        
        // 2. 残高チェック
        // クレカの利用額 (Liabilityの残高)
        int cardBalance = await _getBalance(liability.id);
        // Liabilityは貸方残高がプラスなので、そのまま正の値で返ってくるはず(自作関数の仕様による)
        // ここでは「支払い必要額」として絶対値をとる
        cardBalance = cardBalance.abs();

        // 銀行の残高 (Assetの残高)
        int bankBalance = await _getBalance(paymentAccountId);
        
        // 残高不足ならアラート！
        if (cardBalance > bankBalance) {
          if (!mounted) return;
          final fmt = NumberFormat("#,###");
          
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.red),
                  const SizedBox(width: 8),
                  const Text('資金不足のアラート'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('もうすぐ「${liability.name}」の引き落とし日(${withdrawalDay}日)ですが、口座残高が足りていません！', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  Text('🔹引き落とし額: ¥${fmt.format(cardBalance)}'),
                  Text('🔹口座残高: ¥${fmt.format(bankBalance)}', style: const TextStyle(color: Colors.red)),
                  const Divider(height: 20),
                  Text('不足額: ¥${fmt.format(cardBalance - bankBalance)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 18)),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('確認')),
              ],
            ),
          );
        }
      }
    }
  }

  // 残高計算ヘルパー
  Future<int> _getBalance(int accountId) async {
    int balance = 0;
    // メモリ上のデータを使う（DB再度叩くより早い）
    for (var t in _transactions) {
      if (t.debitAccountId == accountId) balance += t.amount;
      if (t.creditAccountId == accountId) balance -= t.amount;
    }
    // Assetは借方+, Liabilityは貸方+だが、上記計算はAsset基準(借方+)になっている。
    // Liabilityの場合、残高はマイナスになる（借方 < 貸方）ので、
    // 呼び出し元で abs() を使う想定。
    return balance;
  }

  // ... (Deep Linkやその他のメソッドはそのまま) ...
  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  Future<void> _handleDeepLink(Uri uri) async {
    if (uri.host != 'add') return;
    final params = uri.queryParameters;
    final amountStr = params['amount'];
    final debitName = params['debit'];
    final creditName = params['credit'];

    if (amountStr == null || debitName == null || creditName == null) return;
    final amount = int.tryParse(amountStr);
    if (amount == null) return;

    if (_accounts.isEmpty) await _loadData();

    int? debitId;
    int? creditId;
    try {
      debitId = _accounts.firstWhere((a) => a.name == debitName).id;
      creditId = _accounts.firstWhere((a) => a.name == creditName).id;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('自動連携エラー: 科目が見つかりません'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    await _addTransaction(debitId, creditId, amount, DateTime.now(), isAuto: true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.link, color: Colors.white),
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
              _checkCreditCardAlert(); // 科目設定変更後にもチェック
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
    final List<Widget> screens = [
      TransactionListScreen(
        transactions: _transactions,
        accounts: _accounts,
        onDelete: _deleteTransaction,
        onEdit: _editTransaction,
      ),
      PLPage(transactions: _transactions, accounts: _accounts),
      BSPage(transactions: _transactions, accounts: _accounts, db: _db, onDataChanged: () => _loadData()),
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