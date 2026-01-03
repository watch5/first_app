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

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // データリスト（ここがアプリの記憶領域）
  final List<Map<String, dynamic>> _transactions = [
    {'title': 'スーパーで買い物', 'amount': 3500, 'date': '2026/01/03'},
    {'title': '給与振込', 'amount': -250000, 'date': '2025/12/25'},
  ];

  // 画面リストを作る「ゲッター（getter）」
  // これを "get" にすることで、毎回最新の _transactions を画面に渡せます
  List<Widget> get _screens => [
    TransactionListPage(transactions: _transactions), // 0: 明細
    BalanceSheetPage(transactions: _transactions),    // 1: 資産(B/S)
  ];

  void _addTransaction(String title, int amount) {
    setState(() {
      _transactions.insert(0, {
        'title': title,
        'amount': amount,
        'date': '2026/01/04',
      });
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ここで _screens を使います
      body: _screens[_selectedIndex], 
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: '明細'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance), label: '資産(B/S)'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.teal,
        onTap: _onItemTapped,
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: () async {
                // 入力画面へ移動
                final newTransaction = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AddTransactionPage(),
                  ),
                );
                // データが帰ってきたら追加
                if (newTransaction != null) {
                  _addTransaction(newTransaction['title'], newTransaction['amount']);
                }
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

// --- 1. 明細リスト画面 ---
class TransactionListPage extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;

  const TransactionListPage({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const Center(child: Text('データがありません'));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('取引明細'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView.builder(
        itemCount: transactions.length,
        itemBuilder: (context, index) {
          final transaction = transactions[index];
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

// --- 2. 資産（B/S）画面 ---
class BalanceSheetPage extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;

  const BalanceSheetPage({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    // 資産計算ロジック
    int currentAsset = 100000; // 初期貯金 10万円スタートと仮定

    for (var transaction in transactions) {
      // 簡易ロジック：金額をそのまま足し引きします
      // （※本来は借方・貸方のロジックが入りますが、まずは合計の動きを見ます）
      
      // 今回のデータ構造では、支出が「プラスの数字」で入っているので引きます
      // 収入（給与）は「マイナスの数字」で入っているので、本来は足すべきですが
      // サンプルデータに合わせて調整します。
      
      // ここではシンプルに：
      // 「給与」なら足す、「それ以外」なら引く、という動きにしてみましょう
      if (transaction['title'].contains('給与')) {
        // 給与は増える（データがマイナス表記の場合は絶対値を足す）
        currentAsset += (transaction['amount'] as int).abs();
      } else {
        // 買い物は減る
        currentAsset -= (transaction['amount'] as int);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('貸借対照表 (B/S)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '現在の純資産（現金）',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Text(
              '¥$currentAsset',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: currentAsset >= 0 ? Colors.teal : Colors.red,
              ),
            ),
            const SizedBox(height: 30),
            Icon(
              currentAsset >= 0 ? Icons.sentiment_satisfied_alt : Icons.sentiment_very_dissatisfied,
              size: 80,
              color: Colors.grey[300],
            ),
          ],
        ),
      ),
    );
  }
}

// --- 3. 入力画面 ---
class AddTransactionPage extends StatefulWidget {
  const AddTransactionPage({super.key});

  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('入力')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: '品目（例：タクシー）'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '金額（円）'),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final title = _titleController.text;
                  final amount = int.tryParse(_amountController.text) ?? 0;
                  Navigator.of(context).pop({'title': title, 'amount': amount});
                },
                child: const Text('リストに追加'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}