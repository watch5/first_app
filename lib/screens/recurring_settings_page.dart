import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database.dart';

class RecurringSettingsPage extends StatefulWidget {
  final MyDatabase db;
  const RecurringSettingsPage({super.key, required this.db});

  @override
  State<RecurringSettingsPage> createState() => _RecurringSettingsPageState();
}

class _RecurringSettingsPageState extends State<RecurringSettingsPage> {
  List<RecurringTransaction> _list = [];
  List<Account> _accounts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final l = await widget.db.getAllRecurringTransactions();
    final a = await widget.db.getAllAccounts();
    // 日付順にソート
    l.sort((a, b) => a.dayOfMonth.compareTo(b.dayOfMonth));
    setState(() {
      _list = l;
      _accounts = a;
    });
  }

  void _addDialog() {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    final dayController = TextEditingController();
    int? debitId;
    int? creditId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('固定費・サブスクの登録'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: '名前 (例: 家賃, Netflix)', hintText: '給料, 家賃...')),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: dayController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '毎月(日)', hintText: '1-31'))),
                      const SizedBox(width: 10),
                      Expanded(child: TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '金額'))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: debitId,
                    isExpanded: true,
                    hint: const Text('借方 (何に？)'),
                    items: _accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() => debitId = v),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: creditId,
                    isExpanded: true,
                    hint: const Text('貸方 (どこから？)'),
                    items: _accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() => creditId = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
              TextButton(
                onPressed: () async {
                  final amount = int.tryParse(amountController.text);
                  final day = int.tryParse(dayController.text);
                  if (nameController.text.isNotEmpty && amount != null && day != null && debitId != null && creditId != null) {
                    if (day < 1 || day > 31) return; // 簡易バリデーション
                    
                    HapticFeedback.mediumImpact();
                    await widget.db.addRecurringTransaction(nameController.text, day, debitId!, creditId!, amount);
                    _loadData();
                    Navigator.pop(ctx);
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
    return Scaffold(
      appBar: AppBar(title: const Text('固定費・サブスク管理'), actions: [
        IconButton(onPressed: _addDialog, icon: const Icon(Icons.add)),
      ]),
      body: _list.isEmpty 
        ? const Center(child: Text('毎月決まっている支出や収入を登録すると\n資金繰りグラフに自動反映されます。', textAlign: TextAlign.center))
        : ListView.builder(
          itemCount: _list.length,
          itemBuilder: (context, index) {
            final t = _list[index];
            final debitName = _accounts.firstWhere((a) => a.id == t.debitAccountId, orElse: () => const Account(id: -1, name: '?', type: '', costType: '')).name;
            final creditName = _accounts.firstWhere((a) => a.id == t.creditAccountId, orElse: () => const Account(id: -1, name: '?', type: '', costType: '')).name;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(t.dayOfMonth.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('$debitName ← $creditName'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('¥${NumberFormat("#,###").format(t.amount)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.grey, size: 20),
                    onPressed: () async {
                      HapticFeedback.heavyImpact();
                      await widget.db.deleteRecurringTransaction(t.id);
                      _loadData();
                    },
                  ),
                ],
              ),
            );
          },
        ),
    );
  }
}