import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database.dart';

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

  // --- 残高調整ロジック ---
  Future<void> _adjustBalance(int accountId, int currentBalance, int newBalance) async {
    final diff = newBalance - currentBalance;
    if (diff == 0) return;

    final accounts = await widget.db.getAllAccounts();
    Account? adjAccount;
    try {
      adjAccount = accounts.firstWhere((a) => a.name == '残高調整');
    } catch (e) {
      await widget.db.addAccount('残高調整', 'expense', null, 'variable'); // デフォルトは変動費で作成
      final newAccounts = await widget.db.getAllAccounts();
      adjAccount = newAccounts.firstWhere((a) => a.name == '残高調整');
    }

    if (diff > 0) {
      // 資産を増やす (借方:Asset / 貸方:残高調整)
      await widget.db.addTransaction(accountId, adjAccount.id, diff, DateTime.now());
    } else {
      // 資産を減らす (借方:残高調整 / 貸方:Asset)
      await widget.db.addTransaction(adjAccount.id, accountId, diff.abs(), DateTime.now());
    }
  }

  // --- 削除機能 ---
  Future<void> _deleteAccount(Account account) async {
    // 削除確認ダイアログ
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('科目の削除'),
        content: Text(
          '「${account.name}」を削除しますか？\n\n※注意※\nこの科目を使用した過去の取引データもすべて削除されます。\nこの操作は元に戻せません。',
          style: const TextStyle(color: Colors.red),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('削除する', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      HapticFeedback.heavyImpact();
      await widget.db.deleteAccount(account.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${account.name} を削除しました')),
        );
      }
      _loadAccounts(); // リスト再読み込み
    }
  }

  // --- 編集ダイアログ ---
  void _showEditDialog(Account account) async {
    final nameController = TextEditingController(text: account.name);
    final budgetController = TextEditingController(text: account.monthlyBudget?.toString() ?? '');
    final balanceController = TextEditingController();
    
    // 現在の費用区分を初期値にセット
    String currentCostType = account.costType; 

    // 現在の残高を計算して表示する (資産・負債のみ)
    int currentBalance = 0;
    if (account.type == 'asset' || account.type == 'liability') {
      final transactions = await widget.db.getTransactions();
      for (var t in transactions) {
        if (t.debitAccountId == account.id) currentBalance += t.amount;
        if (t.creditAccountId == account.id) currentBalance -= t.amount;
      }
      balanceController.text = currentBalance.toString();
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder( // Dropdownの再描画のためにStatefulBuilderが必要
        builder: (context, setState) {
          return AlertDialog(
            title: Text('${account.name} の編集'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '科目名'),
                  ),
                  const SizedBox(height: 10),
                  
                  // 費用の場合のみ、固定費・変動費を選択
                  if (account.type == 'expense') ...[
                    DropdownButtonFormField<String>(
                      initialValue: currentCostType,
                      decoration: const InputDecoration(labelText: '費用の種類'),
                      items: const [
                        DropdownMenuItem(value: 'variable', child: Text('変動費 (食費・日用品など)')),
                        DropdownMenuItem(value: 'fixed', child: Text('固定費 (家賃・サブスクなど)')),
                      ],
                      onChanged: (val) => setState(() => currentCostType = val!),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: budgetController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '月予算'),
                    ),
                  ],

                  if (account.type == 'asset' || account.type == 'liability')
                     TextField(
                      controller: balanceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '現在の残高',
                        helperText: '変更すると調整データが自動作成されます',
                      ),
                    ),
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween, // ボタンを左右に離す
            actions: [
              // 左側：削除ボタン
              TextButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx); // まず編集ダイアログを閉じる
                  await _deleteAccount(account); // 削除確認フローへ
                },
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text('削除', style: TextStyle(color: Colors.red)),
              ),
              // 右側：キャンセル・保存ボタン
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
                  TextButton(
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      
                      // 1. 残高調整の実行
                      if (account.type == 'asset' || account.type == 'liability') {
                         final newBalance = int.tryParse(balanceController.text) ?? currentBalance;
                         await _adjustBalance(account.id, currentBalance, newBalance);
                      }
                      
                      // 2. 費用区分の更新 (ついでに予算も更新したければここでupdate処理が必要ですが、今回は区分更新のみ追加)
                      if (account.type == 'expense') {
                        await widget.db.updateAccountCostType(account.id, currentCostType);
                        // 予算更新が必要なら updateAccountBudget を呼ぶか、DBメソッドを拡張する必要があります
                        final budget = int.tryParse(budgetController.text);
                        if (budget != null) {
                           await widget.db.updateAccountBudget(account.id, budget);
                        }
                      }

                      _loadAccounts();
                      if (context.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          );
        }
      ),
    );
  }

  // --- 新規追加ダイアログ ---
  void _addAccountDialog() {
    final nameController = TextEditingController();
    final budgetController = TextEditingController();
    final initialBalanceController = TextEditingController(); 
    String type = 'expense';
    String costType = 'variable'; // デフォルトは変動費

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('科目の追加'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: '科目名'), autofocus: true),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    items: const [
                      DropdownMenuItem(value: 'expense', child: Text('費用 (使った)')),
                      DropdownMenuItem(value: 'income', child: Text('収益 (入った)')),
                      DropdownMenuItem(value: 'asset', child: Text('資産 (現金・銀行)')),
                      DropdownMenuItem(value: 'liability', child: Text('負債 (クレカ)')),
                    ],
                    onChanged: (val) => setState(() => type = val!),
                    decoration: const InputDecoration(labelText: '種類'),
                  ),
                  const SizedBox(height: 10),
                  
                  // 費用を選んだときだけ表示
                  if (type == 'expense') ...[
                    DropdownButtonFormField<String>(
                      initialValue: costType,
                      decoration: const InputDecoration(labelText: '費用の種類'),
                      items: const [
                        DropdownMenuItem(value: 'variable', child: Text('変動費 (食費・日用品など)')),
                        DropdownMenuItem(value: 'fixed', child: Text('固定費 (家賃・サブスクなど)')),
                      ],
                      onChanged: (val) => setState(() => costType = val!),
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: budgetController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '月予算')),
                  ],

                  if (type == 'asset' || type == 'liability')
                    TextField(
                      controller: initialBalanceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '現在の残高 (開始残高)'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
              TextButton(
                onPressed: () async {
                  if (nameController.text.isNotEmpty) {
                    HapticFeedback.mediumImpact();
                    final budget = int.tryParse(budgetController.text);
                    
                    // costTypeを渡して作成
                    await widget.db.addAccount(nameController.text, type, budget, costType);
                    
                    // 開始残高設定
                    final accounts = await widget.db.getAllAccounts();
                    final newAccount = accounts.lastWhere((a) => a.name == nameController.text);
                    final initialBalance = int.tryParse(initialBalanceController.text) ?? 0;
                    if (initialBalance > 0) {
                       Account? capitalAccount;
                       try { capitalAccount = accounts.firstWhere((a) => a.name == '元入金'); } 
                       catch (e) { 
                         await widget.db.addAccount('元入金', 'liability', null, 'variable'); 
                         capitalAccount = (await widget.db.getAllAccounts()).firstWhere((a) => a.name == '元入金'); 
                       }
                       
                       if (type == 'asset') {
                         await widget.db.addTransaction(newAccount.id, capitalAccount.id, initialBalance, DateTime.now());
                       } else if (type == 'liability') await widget.db.addTransaction(capitalAccount.id, newAccount.id, initialBalance, DateTime.now());
                    }
                    _loadAccounts();
                    if (context.mounted) Navigator.pop(ctx);
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
          String typeName = '';
          switch (a.type) {
            case 'asset': icon = Icons.account_balance_wallet; color = Colors.blue; typeName='資産'; break;
            case 'income': icon = Icons.savings; color = Colors.green; typeName='収益'; break;
            case 'liability': icon = Icons.credit_card; color = Colors.orange; typeName='負債'; break;
            default: icon = Icons.shopping_bag; color = Colors.redAccent; typeName='費用';
          }
          
          // 費用なら固定費か変動費かを表示
          if (a.type == 'expense') {
            typeName = a.costType == 'fixed' ? '固定費' : '変動費';
          }

          return ListTile(
            leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.2), child: Icon(icon, color: color, size: 20)),
            title: Text(a.name),
            subtitle: a.monthlyBudget != null 
                ? Text('月予算: ¥${fmt.format(a.monthlyBudget)} ($typeName)') 
                : Text(typeName, style: const TextStyle(color: Colors.grey)),
            trailing: const Icon(Icons.edit, size: 16, color: Colors.grey),
            onTap: () => _showEditDialog(a),
          );
        },
      ),
    );
  }
}