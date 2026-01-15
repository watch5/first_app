import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; 
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart'; 
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart'; 

import 'database.dart';
import 'screens/auth_page.dart'; 
import 'screens/budget_page.dart'; 
import 'screens/pl_page.dart';
import 'screens/bs_page.dart';
import 'screens/forecast_page.dart';
import 'screens/add_transaction_page.dart';
import 'screens/account_settings_page.dart';
import 'screens/template_settings_page.dart';
import 'screens/recurring_settings_page.dart'; 
import 'widgets/ad_banner.dart';
import 'screens/calendar_page.dart';
import 'screens/pet_room_page.dart'; 
import 'screens/achievement_page.dart'; 
import 'screens/export_page.dart'; 
import 'screens/import_page.dart'; 
import 'screens/receipt_scan_page.dart'; 
import 'screens/transaction_list_page.dart'; // ★追加: リスト表示用

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ja'); 
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
      
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja'), 
      ],

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
    _checkCreditCardAlert();
    _checkNoMoneyDay(); 
  }
  
  Future<void> _loadData() async {
    final accounts = await _db.getAllAccounts();
    final transactions = await _db.getTransactions();
    setState(() {
      _accounts = accounts;
      _transactions = transactions.reversed.toList();
    });
  }

  // --- 取引操作 ---
  Future<void> _deleteTransaction(int id) async {
    await _db.deleteTransaction(id);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('削除しました')));
    _loadData();
  }

  Future<void> _editTransaction(Transaction t) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => AddTransactionPage(
        accounts: _accounts, 
        db: _db, 
        transaction: t
      )),
    );
    // 戻り値が true (保存または削除完了) ならリロード
    if (result == true) {
      _loadData();
    }
  }

  Future<void> _checkNoMoneyDay() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    
    final lastPopup = prefs.getString('last_no_money_popup');
    if (lastPopup == todayStr) return;

    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStart = DateTime(yesterday.year, yesterday.month, yesterday.day);
    final yesterdayEnd = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);

    int expense = 0;
    final expenseIds = _accounts.where((a) => a.type == 'expense').map((a) => a.id).toList();

    for (var t in _transactions) {
      if (t.date.isAfter(yesterdayStart) && t.date.isBefore(yesterdayEnd)) {
        if (expenseIds.contains(t.debitAccountId)) expense += t.amount;
        if (expenseIds.contains(t.creditAccountId)) expense -= t.amount;
      }
    }

    if (expense == 0 && mounted) {
      await prefs.setString('last_no_money_popup', todayStr);

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('🎉 おめでとうございます！'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sentiment_very_satisfied, color: Colors.amber, size: 60),
              const SizedBox(height: 20),
              const Text(
                '昨日はノーマネーデーでした！\n(出費 0円)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                '素晴らしい節約スキルです✨\n今日も良い一日になりますように。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ありがとう！'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _checkCreditCardAlert() async {
    final now = DateTime.now();
    for (var liability in _accounts.where((a) => a.type == 'liability' && a.withdrawalDay != null && a.paymentAccountId != null)) {
      final withdrawalDay = liability.withdrawalDay!;
      final paymentAccountId = liability.paymentAccountId!;
      DateTime targetDate = DateTime(now.year, now.month, withdrawalDay);
      final diff = targetDate.difference(now).inDays;
      if (diff >= 0 && diff <= 7) {
        int cardBalance = await _getBalance(liability.id);
        cardBalance = cardBalance.abs();
        int bankBalance = await _getBalance(paymentAccountId);
        if (cardBalance > bankBalance) {
          if (!mounted) return;
          final fmt = NumberFormat("#,###");
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ ${liability.name}の引き落とし残高不足の可能性があります\n必要額: ${fmt.format(cardBalance)}円'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  Future<int> _getBalance(int accountId) async {
    int balance = 0;
    for (var t in _transactions) {
      if (t.debitAccountId == accountId) balance += t.amount;
      if (t.creditAccountId == accountId) balance -= t.amount;
    }
    return balance;
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
  }

  Future<void> _handleDeepLink(Uri uri) async {
    // (省略)
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    final List<Widget> screens = [
      // 0: カレンダー (既存)
      CalendarPage(db: _db),
      
      // 1: リスト表示 (★修正: ここにTransactionListScreenを入れる)
      TransactionListScreen(
        transactions: _transactions, 
        accounts: _accounts, 
        onDelete: _deleteTransaction, 
        onEdit: _editTransaction
      ),

      // 2: 予算
      BudgetPage(transactions: _transactions, accounts: _accounts, onDataChanged: _loadData), 
      
      // 3: 損益
      PLPage(transactions: _transactions, accounts: _accounts),
      
      // 4: 資産 (B/S)
      BSPage(transactions: _transactions, accounts: _accounts, db: _db, onDataChanged: () => _loadData()), 
    ];

    // NavigationBarの項目とscreensのインデックスを合わせる必要があるため調整
    // 現在の順番: Calendar, List(New), Budget, PL, BS
    // BottomNavのラベル: カレンダー, リスト, 予算, 損益, 資産
    // Forecast(予測)は一旦外すか、タブを増やすかですが、一旦「リスト」を見やすくするために5つにします。

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dualy'),
      ),
      
      // ドロワー (サイドメニュー)
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: colorScheme.primary),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.account_balance_wallet, color: Colors.white, size: 48),
                  SizedBox(height: 10),
                  Text('Dualy', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  Text('複式簿記の家計簿アプリ', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            
            ListTile(
              leading: const Icon(Icons.timeline, color: Colors.indigo), // 予測ページはここへ移動
              title: const Text('資金繰り予測'),
              onTap: () {
                Navigator.pop(context); 
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => ForecastPage(db: _db)));
              },
            ),

            ListTile(
              leading: const Icon(Icons.pets, color: Colors.orange),
              title: const Text('資産ペット部屋'),
              subtitle: const Text('減価償却を楽しく管理'),
              onTap: () {
                Navigator.pop(context); 
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => PetRoomPage(db: _db)));
              },
            ),

            ListTile(
              leading: const Icon(Icons.emoji_events, color: Colors.amber),
              title: const Text('実績博物館'),
              subtitle: const Text('獲得したトロフィーを確認'),
              onTap: () {
                Navigator.pop(context); 
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => AchievementPage(db: _db)));
              },
            ),

            ListTile(
              leading: const Icon(Icons.document_scanner, color: Colors.indigo),
              title: const Text('レシート読み込み'),
              subtitle: const Text('AIで文字を認識して記帳'),
              onTap: () async {
                Navigator.pop(context); 
                final result = await Navigator.of(context).push(MaterialPageRoute(builder: (context) => ReceiptScanPage(db: _db)));
                // 保存が行われたらリロード
                if (result == true) _loadData();
              },
            ),

            const Divider(),
            
            ListTile(
              leading: const Icon(Icons.file_download, color: Colors.teal),
              title: const Text('データ出力'),
              onTap: () {
                Navigator.pop(context); 
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => ExportPage(db: _db)));
              },
            ),

            ListTile(
              leading: const Icon(Icons.file_upload, color: Colors.orange),
              title: const Text('データ取り込み'),
              onTap: () async {
                Navigator.pop(context); 
                await Navigator.of(context).push(MaterialPageRoute(builder: (context) => ImportPage(db: _db)));
                _loadData(); 
              },
            ),

            const Divider(),
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
              child: Text('設定・管理', style: TextStyle(color: colorScheme.outline)),
            ),

            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('科目の管理'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.of(context).push(MaterialPageRoute(builder: (context) => AccountSettingsPage(db: _db)));
                _loadData(); 
              },
            ),
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('固定費・サブスクの管理'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.of(context).push(MaterialPageRoute(builder: (context) => RecurringSettingsPage(db: _db)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.bookmark),
              title: const Text('テンプレートの管理'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.of(context).push(MaterialPageRoute(builder: (context) => TemplateSettingsPage(db: _db)));
              },
            ),
          ],
        ),
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
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'カレンダー'),
          NavigationDestination(icon: Icon(Icons.list), label: 'リスト'), // ★変更
          NavigationDestination(icon: Icon(Icons.pie_chart), label: '予算'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: '損益'),
          NavigationDestination(icon: Icon(Icons.account_balance), label: '資産'),
        ],
      ),
      
      floatingActionButton: (_selectedIndex == 0 || _selectedIndex == 1)
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'scan_fab', 
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => ReceiptScanPage(db: _db)),
                    );
                    if (result == true) _loadData();
                  },
                  backgroundColor: colorScheme.secondaryContainer,
                  tooltip: 'レシート読み込み',
                  child: const Icon(Icons.document_scanner),
                ),
                const SizedBox(height: 12),
                
                FloatingActionButton.extended(
                  heroTag: 'add_fab', 
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    if (_accounts.isEmpty) return;
                    
                    final result = await Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => AddTransactionPage(accounts: _accounts, db: _db)),
                    );
                    
                    if (result == true) {
                      _loadData();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('記帳しました！')));
                      }
                    }
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('記帳'),
                ),
              ],
            )
          : null,
    );
  }
}