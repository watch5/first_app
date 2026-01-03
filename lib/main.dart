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

  // ★重要：データリストをここで管理します（最初はダミーデータ）
  List<Map<String, dynamic>> _transactions = [
    {'title': 'スーパーで買い物', 'amount': 3500, 'date': '2026/01/03'},
    {'title': '給与振込', 'amount': -250000, 'date': '2025/12/25'},
  ];

  // 新しい取引を追加するメソッド
  void _addTransaction(String title, int amount) {
    setState(() {
      _transactions.insert(0, { // リストの先頭(0番目)に追加
        'title': title,
        'amount': amount,
        'date': '2026/01/04', // 日付は一旦固定で今日にしておきます
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
    // 画面のリスト（データを渡すためにここで作ります）
    final List<Widget> _screens = [
      TransactionListPage(transactions: _transactions), // データを渡す！
      const BalanceSheetPage(),
    ];

    return Scaffold(
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
                // ★ここが魔法のポイント
                // 入力画面へ行き、帰ってくるのを「待つ(await)」
                final newTransaction = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AddTransactionPage(),
                  ),
                );

                // もしデータを持って帰ってきたら、リストに追加する
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
  // 親からデータをもらうための受け口
  final List<Map<String, dynamic>> transactions;

  const TransactionListPage({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    // データが空っぽの時の表示
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
  const BalanceSheetPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('貸借対照表 (B/S)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: const Center(child: Text('資産画面はこれから！')),
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
  // 入力された文字を捕まえる「網（コントローラー）」
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
              controller: _titleController, // 網をセット
              decoration: const InputDecoration(labelText: '品目（例：タクシー）'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _amountController, // 網をセット
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '金額（円）'),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // 保存ボタンが押されたら
                  final title = _titleController.text;
                  final amount = int.tryParse(_amountController.text) ?? 0;

                  // データをまとめて、元の画面に「返す(pop)」
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