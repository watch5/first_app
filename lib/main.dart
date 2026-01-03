import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My家計簿',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

// 画面の状態（どのタブを選んでいるか）を管理するために StatefulWidget を使います
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // 今選んでいるタブの番号（0: 明細, 1: 資産）
  int _selectedIndex = 0;

  // 表示する画面のリスト
  final List<Widget> _screens = [
    const TransactionListPage(), // 0番目: 明細リスト
    const BalanceSheetPage(),    // 1番目: 資産（B/S）
  ];

  // タブがタップされた時の処理
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex], // 選ばれた画面を表示
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: '明細',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet), // お財布のアイコン
            label: '資産(B/S)',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.teal,
        onTap: _onItemTapped,
      ),
      // 入力ボタンは「明細」タブの時だけ表示する小技
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

// --- 以下、各画面の中身 ---

// 1. 明細リスト画面（さっき作ったやつです）
class TransactionListPage extends StatelessWidget {
  const TransactionListPage({super.key});

  @override
  Widget build(BuildContext context) {
    // ダミーデータ
    final List<Map<String, dynamic>> dummyTransactions = [
      {'title': 'スーパーで買い物', 'amount': 3500, 'date': '2026/01/03'},
      {'title': 'カフェラテ', 'amount': 550, 'date': '2026/01/03'},
      {'title': '書籍購入（技術書）', 'amount': 2800, 'date': '2026/01/02'},
      {'title': '給与振込', 'amount': -250000, 'date': '2025/12/25'},
      {'title': 'コンビニ', 'amount': 800, 'date': '2025/12/24'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('取引明細'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView.builder(
        itemCount: dummyTransactions.length,
        itemBuilder: (context, index) {
          final transaction = dummyTransactions[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: ListTile(
              leading: const Icon(Icons.shopping_bag_outlined),
              title: Text(transaction['title']),
              subtitle: Text(transaction['date']),
              trailing: Text(
                '¥${transaction['amount']}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          );
        },
      ),
    );
  }
}

// 2. 資産（B/S）画面（新登場！）
class BalanceSheetPage extends StatelessWidget {
  const BalanceSheetPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('貸借対照表 (B/S)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.account_balance, size: 100, color: Colors.grey),
            SizedBox(height: 20),
            Text(
              'ここに資産バランスが表示されます',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            Text(
              '（現金、銀行口座、クレカ負債など）',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}