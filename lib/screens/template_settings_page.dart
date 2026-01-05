import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database.dart'; // 親フォルダのdatabase.dartを参照

class TemplateSettingsPage extends StatefulWidget {
  final MyDatabase db;
  const TemplateSettingsPage({super.key, required this.db});

  @override
  State<TemplateSettingsPage> createState() => _TemplateSettingsPageState();
}

class _TemplateSettingsPageState extends State<TemplateSettingsPage> {
  List<Template> _templates = [];
  List<Account> _accounts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final t = await widget.db.getAllTemplates();
    final a = await widget.db.getAllAccounts();
    setState(() {
      _templates = t;
      _accounts = a;
    });
  }

  void _addTemplateDialog() {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    int? debitId;
    int? creditId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('テンプレートの追加'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: '名前 (例: 家賃)')),
                  TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '金額')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: debitId,
                    hint: const Text('借方 (何に？)'),
                    items: _accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                    onChanged: (v) => setState(() => debitId = v),
                  ),
                  DropdownButtonFormField<int>(
                    value: creditId,
                    hint: const Text('貸方 (どうやって？)'),
                    items: _accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
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
                  if (nameController.text.isNotEmpty && amount != null && debitId != null && creditId != null) {
                    HapticFeedback.mediumImpact();
                    await widget.db.addTemplate(nameController.text, debitId!, creditId!, amount);
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
      appBar: AppBar(title: const Text('テンプレート管理'), actions: [
        IconButton(onPressed: _addTemplateDialog, icon: const Icon(Icons.add)),
      ]),
      body: _templates.isEmpty 
        ? const Center(child: Text('テンプレートがありません\n右上の＋ボタンから追加してください', textAlign: TextAlign.center))
        : ListView.builder(
          itemCount: _templates.length,
          itemBuilder: (context, index) {
            final t = _templates[index];
            final debitName = _accounts.firstWhere((a) => a.id == t.debitAccountId, orElse: () => const Account(id: -1, name: '?', type: '')).name;
            final creditName = _accounts.firstWhere((a) => a.id == t.creditAccountId, orElse: () => const Account(id: -1, name: '?', type: '')).name;

            return ListTile(
              title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('$debitName ← $creditName / ¥${NumberFormat("#,###").format(t.amount)}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.grey),
                onPressed: () async {
                  HapticFeedback.heavyImpact();
                  await widget.db.deleteTemplate(t.id);
                  _loadData();
                },
              ),
            );
          },
        ),
    );
  }
}