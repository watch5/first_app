import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';
import '../database.dart';

class AddTransactionPage extends StatefulWidget {
  final List<Account> accounts;
  final MyDatabase db;
  final Transaction? transaction;
  final Transaction? initialData;

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
  // ★ここに取得したAPIキーを入れてください
  final String _apiKey = 'AIzaSyAjn7KgHXI8tx6lHGgmNiD7EsaaxTGWaXA';

  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  
  DateTime _date = DateTime.now();
  int? _debitId;
  int? _creditId;
  bool _isSuggesting = false;

  @override
  void initState() {
    super.initState();
    if (widget.transaction != null) {
      final t = widget.transaction!;
      _amountController.text = t.amount.toString();
      _noteController.text = t.note ?? '';
      _date = t.date;
      _debitId = t.debitAccountId;
      _creditId = t.creditAccountId;
    } else if (widget.initialData != null) {
      final t = widget.initialData!;
      _amountController.text = t.amount > 0 ? t.amount.toString() : '';
      _noteController.text = t.note ?? '';
      _date = t.date;
      _debitId = t.debitAccountId > 0 ? t.debitAccountId : null;
      _creditId = t.creditAccountId > 0 ? t.creditAccountId : null;
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

  Future<void> _suggestCategories() async {
    final note = _noteController.text;
    if (note.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('メモを入力してから押してください')));
      return;
    }

    setState(() => _isSuggesting = true);
    FocusScope.of(context).unfocus();

    try {
      final accounts = widget.accounts;
      final accountListStr = accounts.map((a) => "${a.id}:${a.name}(${a.type})").join(", ");

      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey);
      
      final prompt = """
        家計簿アプリの入力補助です。
        メモ「$note」から、最も適切な「借方科目(debitId)」と「貸方科目(creditId)」を推測してください。
        選択肢: $accountListStr
        ルール: 不明なら-1。JSONキー: "debitId", "creditId"。JSONのみ出力。
      """;

      final response = await model.generateContent([Content.text(prompt)]);
      final text = response.text;
      if (text == null) throw Exception('Empty response');

      final cleanJson = text.replaceAll(RegExp(r'```json|```'), '').trim();
      final data = jsonDecode(cleanJson);

      final suggestedDebit = data['debitId'] is int ? data['debitId'] : int.tryParse(data['debitId'].toString()) ?? -1;
      final suggestedCredit = data['creditId'] is int ? data['creditId'] : int.tryParse(data['creditId'].toString()) ?? -1;

      setState(() {
        if (suggestedDebit > 0) _debitId = suggestedDebit;
        if (suggestedCredit > 0) _creditId = suggestedCredit;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AIが科目を自動選択しました✨')));
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AIエラー: $e')));
    } finally {
      setState(() => _isSuggesting = false);
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
    if (picked != null) setState(() => _date = picked);
  }

  // ★削除機能
  Future<void> _delete() async {
    if (widget.transaction == null) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除しますか？'),
        content: const Text('この取引データを削除します。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.db.deleteTransaction(widget.transaction!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('削除しました')));
        Navigator.pop(context, true); // trueを返して親画面で更新
      }
    }
  }

  Future<void> _save() async {
    final amount = int.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('金額を入力してください')));
      return;
    }
    if (_debitId == null || _creditId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('借方・貸方を選択してください')));
      return;
    }

    try {
      if (widget.transaction != null) {
        await widget.db.updateTransaction(
          widget.transaction!.id,
          _debitId!,
          _creditId!,
          amount,
          _date,
          note: _noteController.text,
        );
      } else {
        await widget.db.addTransaction(
          _debitId!,
          _creditId!,
          amount,
          _date,
          note: _noteController.text,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存しました')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('エラー: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.transaction != null ? '取引の編集' : '記帳'),
        actions: [
          // ★編集モードの時だけ削除ボタンを表示
          if (widget.transaction != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _delete,
              tooltip: '削除',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              title: Text('日付: ${DateFormat('yyyy/MM/dd (E)', 'ja').format(_date)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectDate,
              tileColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '金額 (円)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.currency_yen)),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _noteController,
                    decoration: const InputDecoration(labelText: 'メモ (店名など)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.note)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _isSuggesting ? null : _suggestCategories,
                  icon: _isSuggesting 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : const Icon(Icons.auto_awesome, color: Colors.orange),
                  tooltip: 'AIで科目を推測',
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 8.0, bottom: 16.0),
              child: Align(alignment: Alignment.centerLeft, child: Text('メモを入れて✨を押すと、科目を自動で選びます', style: TextStyle(fontSize: 10, color: Colors.grey))),
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _debitId,
                    decoration: const InputDecoration(labelText: '借方', border: OutlineInputBorder()),
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
                    decoration: const InputDecoration(labelText: '貸方', border: OutlineInputBorder()),
                    items: widget.accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                    onChanged: (v) => setState(() => _creditId = v),
                  ),
                ),
              ],
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