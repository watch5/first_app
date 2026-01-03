import 'package:flutter/material.dart';
import 'database.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My複式家計簿',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo), // 少し大人っぽい色に
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
  
  // データベース
  final MyDatabase _db = MyDatabase();
  
  // データリスト
  List<Transaction> _transactions = [];
  List<Account> _accounts = []; // 勘定科目リスト（食費、現金など）

  @override
  void initState() {
    super.initState();
    _initData();
  }

  // 初期化とデータ読み込み
  Future<void> _initData() async {
    // 1. 科目が空なら初期データ（現金、食費など）を作る
    await _db.seedDefaultAccounts();
    // 2. データを読み込む
    await _loadData();
  }

  Future<void> _loadData() async {
    final accounts = await _db.getAllAccounts();
    final transactions = await _db.getTransactions();
    setState(() {
      _accounts = accounts;
      // 新しい順に表示
      _transactions = transactions.reversed.toList();
    });
  }

  // IDから科目名を探す便利関数
  String _getAccountName(int id) {
    // リストからIDが一致するものを探す
    final account = _accounts.firstWhere((a) => a.id == id, 
        orElse: () => const Account(id: -1, name: '不明', type: 'unknown'));
    return account.name;
  }

  // 追加処理
  Future<void> _addTransaction(int debitId, int creditId, int amount) async {
    await _db.addTransaction(debitId, creditId, amount, DateTime.now());
    await _loadData();
  }

  // 削除処理
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
    // 画面切り替え
    final List<Widget> screens = [
      TransactionListPage(
        transactions: _transactions,
        getAccountName: _getAccountName,
        onDelete: _deleteTransaction,
      ),
      BalanceSheetPage(
        transactions: _transactions,
        accounts: _accounts,
      ),
    ];

    return Scaffold(
      body: screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: '明細'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance), label: '資産(B/S)'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.indigo,
        onTap: _onItemTapped,
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: () async {
                // 科目データがまだ読み込めていなければ何もしない
                if (_accounts.isEmpty) return;
                
                // 入力画面へ（科目リストを渡す）
                final result = await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => AddTransactionPage(accounts: _accounts),
                  ),
                );
                
                if (result != null) {
                  // 登録実行
                  await _addTransaction(
                    result['debitId'], 
                    result['creditId'], 
                    result['amount']
                  );
                }
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

// --- 1. 明細リスト画面（複式表示） ---
class TransactionListPage extends StatelessWidget {
  final List<Transaction> transactions;
  final String Function(int) getAccountName; // 親から借りた「名前検索メガネ」
  final Function(int) onDelete;

  const TransactionListPage({
    super.key,
    required this.transactions,
    required this.getAccountName,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const Center(child: Text('データがありません'));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('取引明細'), backgroundColor: Colors.indigo[100]),
      body: ListView.builder(
        itemCount: transactions.length,
        itemBuilder: (context, index) {
          final t = transactions[index];
          // 借方（左）と貸方（右）の名前を取得
          final debitName = getAccountName(t.debitAccountId);
          final creditName = getAccountName(t.creditAccountId);

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: ListTile(
              // 左側に「何に使ったか」
              title: Text(
                '$debitName  ⬅︎  $creditName',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('${t.date.year}/${t.date.month}/${t.date.day}'),
              trailing: Text(
                '¥${t.amount}',
                style: const TextStyle(fontSize: 18),
              ),
              onLongPress: () {
                // 削除確認ダイアログ
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('削除しますか？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
                      TextButton(
                        onPressed: () {
                          onDelete(t.id);
                          Navigator.pop(ctx);
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

// --- 2. 資産（B/S）画面（本格計算） ---
class BalanceSheetPage extends StatelessWidget {
  final List<Transaction> transactions;
  final List<Account> accounts;

  const BalanceSheetPage({super.key, required this.transactions, required this.accounts});

  @override
  Widget build(BuildContext context) {
    // 資産科目だけを抽出（現金、銀行など）
    final assetAccounts = accounts.where((a) => a.type == 'asset').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('貸借対照表 (B/S)'), backgroundColor: Colors.indigo[100]),
      body: ListView.builder(
        itemCount: assetAccounts.length,
        itemBuilder: (context, index) {
          final account = assetAccounts[index];
          
          // 残高計算：(借方に来た金額) - (貸方に行った金額)
          // 例：現金が増えた(借方) - 現金を使った(貸方)
          int balance = 0;
          for (var t in transactions) {
            if (t.debitAccountId == account.id) balance += t.amount;
            if (t.creditAccountId == account.id) balance -= t.amount;
          }

          return Card(
            margin: const EdgeInsets.all(10),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_wallet, color: Colors.indigo),
                      const SizedBox(width: 10),
                      Text(account.name, style: const TextStyle(fontSize: 20)),
                    ],
                  ),
                  Text(
                    '¥$balance',
                    style: TextStyle(
                      fontSize: 24, 
                      fontWeight: FontWeight.bold,
                      color: balance >= 0 ? Colors.black : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- 3. 入力画面（プルダウン選択式！） ---
class AddTransactionPage extends StatefulWidget {
  final List<Account> accounts;
  const AddTransactionPage({super.key, required this.accounts});

  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  final _amountController = TextEditingController();
  
  // 選択されたID
  int? _debitId;  // 借方（例：食費）
  int? _creditId; // 貸方（例：現金）

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('記帳')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 金額入力
            const Text('金額', style: TextStyle(fontSize: 16)),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              autofocus: true, // 開いたらすぐ入力できるようにする
              decoration: const InputDecoration(
                hintText: '¥0',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 30),

            // 借方（増えたもの/費用）の選択
            const Text('何に使った？ (借方)', style: TextStyle(fontSize: 16, color: Colors.indigo)),
            DropdownButton<int>(
              value: _debitId,
              isExpanded: true,
              hint: const Text('選択してください（例：食費）'),
              items: widget.accounts.map((account) {
                return DropdownMenuItem(
                  value: account.id,
                  child: Text(account.name), // 科目名を表示
                );
              }).toList(),
              onChanged: (val) => setState(() => _debitId = val),
            ),
            const SizedBox(height: 20),

            // 貸方（減ったもの/支払い元）の選択
            const Text('どう払った？ (貸方)', style: TextStyle(fontSize: 16, color: Colors.green)),
            DropdownButton<int>(
              value: _creditId,
              isExpanded: true,
              hint: const Text('選択してください（例：現金）'),
              items: widget.accounts.map((account) {
                return DropdownMenuItem(
                  value: account.id,
                  child: Text(account.name),
                );
              }).toList(),
              onChanged: (val) => setState(() => _creditId = val),
            ),
            const SizedBox(height: 40),

            // 登録ボタン
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final amount = int.tryParse(_amountController.text);
                  // 全て入力されていたら保存
                  if (amount != null && _debitId != null && _creditId != null) {
                    Navigator.of(context).pop({
                      'debitId': _debitId,
                      'creditId': _creditId,
                      'amount': amount,
                    });
                  }
                },
                child: const Text('記帳する', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}