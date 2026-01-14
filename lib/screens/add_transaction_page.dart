import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database.dart';

class AddTransactionPage extends StatefulWidget {
  final List<Account> accounts;
  final MyDatabase db;
  final Transaction? transaction; // 編集用 (IDあり)
  final Transaction? initialData; // ★追加: レシート等の初期値用 (ID無視)

  const AddTransactionPage({
    super.key,
    required this.accounts,
    required this.db,
    this.transaction,
    this.initialData,
  });

  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  
  DateTime _date = DateTime.now();
  int? _debitId;
  int? _creditId;

  @override
  void initState() {
    super.initState();
    // 編集モード
    if (widget.transaction != null) {
      final t = widget.transaction!;
      _amountController.text = t.amount.toString();
      _noteController.text = t.note ?? '';
      _date = t.date;
      _debitId = t.debitAccountId;
      _creditId = t.creditAccountId;
    } 
    // ★追加: レシート読み込み等からの初期値モード
    else if (widget.initialData != null) {
      final t = widget.initialData!;
      _amountController.text = t.amount > 0 ? t.amount.toString() : '';
      _noteController.text = t.note ?? '';
      _date = t.date;
      // 科目などは未定の状態にするか、推測ロジックを入れる
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('ja'),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _onDebitChanged(int? val) async {
    setState(() => _debitId = val);
    if (val != null && _creditId == null) {
      final frequentCreditId = await widget.db.getMostFrequentCreditId(val);
      if (frequentCreditId != null) {
        setState(() => _creditId = frequentCreditId);
      }
    }
  }

  void _save() {
    final amount = int.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('金額を入力してください')));
      return;
    }
    if (_debitId == null || _creditId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('借方・貸方を選択してください')));
      return;
    }

    // 戻り値としてデータを返す
    Navigator.pop(context, {
      // transactionがある場合のみIDを返す（編集モード）
      if (widget.transaction != null) 'id': widget.transaction!.id,
      'debitId': _debitId,
      'creditId': _creditId,
      'amount': amount,
      'date': _date,
      'note': _noteController.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.transaction != null ? '取引の編集' : '記帳'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              title: Text('日付: ${DateFormat('yyyy/MM/dd (E)', 'ja').format(_date)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectDate,
              tileColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _debitId,
                    decoration: const InputDecoration(labelText: '借方 (何に？)', border: OutlineInputBorder()),
                    items: widget.accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                    onChanged: _onDebitChanged,
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.arrow_forward),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _creditId,
                    decoration: const InputDecoration(labelText: '貸方 (どこから？)', border: OutlineInputBorder()),
                    items: widget.accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                    onChanged: (v) => setState(() => _creditId = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '金額 (円)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.currency_yen),
              ),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'メモ (任意)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.note),
              ),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('保存', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}