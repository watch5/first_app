import 'package:flutter/material.dart';
import 'database.dart'; // さっき作ったデータベースを読み込む

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
  
  // ★ データベースのインスタンスを作成
  final MyDatabase _db = MyDatabase();
  
  // データリスト（型が 'Transaction' に変わりました！）
  List<Transaction> _transactions = [];

  @override
  void initState() {
    super.initState();
    // アプリ起動時にデータを読み込む
    _loadData();
  }

  // データベースから全データを取ってくる処理
  Future<void> _loadData() async {
    final list = await _db.getAllTransactions();
    setState(() {
      // 日付の新しい順（降順）に並べ替えてセット
      _transactions = list.reversed.toList();
    });
  }

  // データを追加する処理
  Future<void> _addTransaction(String title, int amount) async {
    // データベースに保存
    await _db.addTransaction(title, amount, DateTime.now());
    // 画面を更新（再読み込み）
    await _loadData();
  }

  // データを削除する処理（長押しで消せるようにしました）
  Future<void> _deleteTransaction(int id) async {
    await _db.deleteTransaction(id);
    await _loadData();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 画面リスト
    final List<Widget> screens = [
      TransactionListPage(
        transactions: _transactions,
        onDelete: _deleteTransaction, // 削除機能も渡す
      ),
      BalanceSheetPage(transactions: _transactions),
    ];

    return Scaffold(
      body: screens[_selectedIndex],
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
                final newTransaction = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AddTransactionPage(),
                  ),
                );
                if (newTransaction != null) {
                  // データベースに追加
                  await _addTransaction(newTransaction['title'], newTransaction['amount']);
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
  final List<Transaction> transactions; // 型変更
  final Function(int) onDelete; // 削除用の関数

  const TransactionListPage({
    super.key,
    required this.transactions,
    required this.onDelete,
  });

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
              // ★ データベースのデータは ['title'] ではなく .title でアクセスします
              title: Text(transaction.title),
              subtitle: Text(
                '${transaction.date.year}/${transaction.date.month}/${transaction.date.day}',
              ),
              trailing: Text(
                '¥${transaction.amount}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              // 長押しで削除
              onLongPress: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('削除しますか？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('キャンセル'),
                      ),
                      TextButton(
                        onPressed: () {
                          onDelete(transaction.id); // 削除実行
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('削除', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// --- 2. 資産（B/S）画面 ---
class BalanceSheetPage extends StatelessWidget {
  final List<Transaction> transactions; // 型変更

  const BalanceSheetPage({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    int currentAsset = 100000; // 初期設定

    for (var transaction in transactions) {
      if (transaction.title.contains('給与')) {
        currentAsset += transaction.amount.abs();
      } else {
        currentAsset -= transaction.amount;
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

// --- 3. 入力画面（ここは変更なし） ---
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