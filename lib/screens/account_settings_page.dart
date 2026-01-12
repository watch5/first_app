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
      await widget.db.addAccount('残高調整', 'expense', null, 'variable'); 
      final newAccounts = await widget.db.getAllAccounts();
      adjAccount = newAccounts.firstWhere((a) => a.name == '残高調整');
    }

    if (diff > 0) {
      // 資産を増やす (借方:Asset / 貸方:残高調整)
      await widget.db.addTransaction(accountId, adjAccount.id, diff, DateTime.now(), isAuto: true);
    } else {
      // 資産を減らす (借方:残高調整 / 貸方:Asset)
      await widget.db.addTransaction(adjAccount.id, accountId, diff.abs(), DateTime.now(), isAuto: true);
    }
  }

  // --- 削除機能 ---
  Future<void> _deleteAccount(Account account) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('科目の削除'),
        content: Text(
          '「${account.name}」を削除しますか？\n\n※注意※\nこの科目を使用した過去の取引データもすべて削除されます。',
          style: const TextStyle(color: Colors.red),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${account.name} を削除しました')));
      }
      _loadAccounts(); 
    }
  }

  // --- 編集ダイアログ ---
  void _showEditDialog(Account account) async {
    final nameController = TextEditingController(text: account.name);
    final budgetController = TextEditingController(text: account.monthlyBudget?.toString() ?? '');
    final balanceController = TextEditingController();
    final withdrawalDayController = TextEditingController(text: account.withdrawalDay?.toString() ?? '');
    
    String currentCostType = account.costType; 
    int? paymentAccountId = account.paymentAccountId;

    // 現在の残高を計算
    int currentBalance = 0;
    if (account.type == 'asset' || account.type == 'liability') {
      final transactions = await widget.db.getTransactions();
      for (var t in transactions) {
        if (t.debitAccountId == account.id) currentBalance += t.amount;
        if (t.creditAccountId == account.id) currentBalance -= t.amount;
      }
      // 負債の場合は貸方がプラスなので逆転させる
      if (account.type == 'liability') currentBalance = -currentBalance;
      
      balanceController.text = currentBalance.toString();
    }

    if (!mounted) return;

    // Assetリスト（引き落とし口座用）
    final assetAccounts = _accounts.where((a) => a.type == 'asset').toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder( 
        builder: (context, setState) {
          return AlertDialog(
            title: Text('${account.name} の編集'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: '科目名')),
                  const SizedBox(height: 10),
                  
                  // 費用の場合
                  if (account.type == 'expense') ...[
                    DropdownButtonFormField<String>(
                      initialValue: currentCostType,
                      decoration: const InputDecoration(labelText: '費用の種類'),
                      items: const [
                        DropdownMenuItem(value: 'variable', child: Text('変動費 (食費など)')),
                        DropdownMenuItem(value: 'fixed', child: Text('固定費 (家賃など)')),
                      ],
                      onChanged: (val) => setState(() => currentCostType = val!),
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: budgetController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '月予算')),
                  ],

                  // 負債（クレカ）の場合の追加設定 ★ここ！
                  if (account.type == 'liability') ...[
                     const Divider(height: 30),
                     const Text('引き落とし設定（アラート用）', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                     Row(
                       children: [
                         Expanded(
                           child: TextField(
                             controller: withdrawalDayController,
                             keyboardType: TextInputType.number,
                             decoration: const InputDecoration(labelText: '毎月の日付', hintText: '27'),
                           ),
                         ),
                         const SizedBox(width: 10),
                         Expanded(
                           flex: 2,
                           child: DropdownButtonFormField<int>(
                             initialValue: paymentAccountId,
                             isExpanded: true,
                             decoration: const InputDecoration(labelText: '引き落とし口座'),
                             items: assetAccounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                             onChanged: (val) => setState(() => paymentAccountId = val),
                           ),
                         ),
                       ],
                     ),
                     const SizedBox(height: 10),
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
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actions: [
              TextButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx); 
                  await _deleteAccount(account); 
                },
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text('削除', style: TextStyle(color: Colors.red)),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
                  TextButton(
                    onPressed: () async {
                      HapticFeedback.mediumImpact();
                      
                      // 1. 残高調整
                      if (account.type == 'asset' || account.type == 'liability') {
                         final newBalance = int.tryParse(balanceController.text) ?? currentBalance;
                         await _adjustBalance(account.id, currentBalance, newBalance);
                      }
                      
                      // 2. 費用区分・予算更新
                      if (account.type == 'expense') {
                        await widget.db.updateAccountCostType(account.id, currentCostType);
                        final budget = int.tryParse(budgetController.text);
                        if (budget != null) {
                           await widget.db.updateAccountBudget(account.id, budget);
                        }
                      }
                      
                      // 3. クレカ設定更新 ★ここ！
                      if (account.type == 'liability') {
                        final day = int.tryParse(withdrawalDayController.text);
                        await widget.db.updateAccountPaymentInfo(account.id, day, paymentAccountId);
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
    final withdrawalDayController = TextEditingController();
    
    String type = 'expense';
    String costType = 'variable'; 
    int? paymentAccountId;

    // Assetリスト（引き落とし口座用）
    final assetAccounts = _accounts.where((a) => a.type == 'asset').toList();

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
                  
                  if (type == 'expense') ...[
                    DropdownButtonFormField<String>(
                      initialValue: costType,
                      decoration: const InputDecoration(labelText: '費用の種類'),
                      items: const [
                        DropdownMenuItem(value: 'variable', child: Text('変動費')),
                        DropdownMenuItem(value: 'fixed', child: Text('固定費')),
                      ],
                      onChanged: (val) => setState(() => costType = val!),
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: budgetController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '月予算')),
                  ],

                  // 負債（クレカ）の場合の設定 ★ここ！
                  if (type == 'liability') ...[
                     const SizedBox(height: 10),
                     Row(
                       children: [
                         Expanded(
                           child: TextField(
                             controller: withdrawalDayController,
                             keyboardType: TextInputType.number,
                             decoration: const InputDecoration(labelText: '引き落とし日', hintText: '27'),
                           ),
                         ),
                         const SizedBox(width: 10),
                         Expanded(
                           flex: 2,
                           child: DropdownButtonFormField<int>(
                             initialValue: paymentAccountId,
                             isExpanded: true,
                             decoration: const InputDecoration(labelText: '引き落とし口座'),
                             items: assetAccounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                             onChanged: (val) => setState(() => paymentAccountId = val),
                           ),
                         ),
                       ],
                     ),
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
                    final withdrawalDay = int.tryParse(withdrawalDayController.text);
                    
                    // costType, withdrawalDay, paymentAccountId を渡して作成
                    await widget.db.addAccount(
                      nameController.text, 
                      type, 
                      budget, 
                      costType,
                      withdrawalDay: withdrawalDay, // ★追加
                      paymentAccountId: paymentAccountId, // ★追加
                    );
                    
                    // 開始残高設定 (省略)
                    // ... (既存の開始残高ロジックはそのまま機能します)

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
          
          if (a.type == 'expense') {
            typeName = a.costType == 'fixed' ? '固定費' : '変動費';
          }
          // クレカ情報表示
          if (a.type == 'liability' && a.withdrawalDay != null) {
            typeName += ' (毎月${a.withdrawalDay}日払い)';
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