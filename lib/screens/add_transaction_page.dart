import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database.dart';

class AddTransactionPage extends StatefulWidget {
  final List<Account> accounts;
  final MyDatabase db;
  final Transaction? transaction; // 編集する場合の元データ

  const AddTransactionPage({
    super.key, 
    required this.accounts, 
    required this.db,
    this.transaction, // nullなら新規作成、あれば編集モード
  });

  @override
  State<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends State<AddTransactionPage> {
  final _amountController = TextEditingController();
  int? _debitId;
  int? _creditId;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    // 編集モードなら初期値をセットする
    if (widget.transaction != null) {
      final t = widget.transaction!;
      _amountController.text = t.amount.toString();
      _debitId = t.debitAccountId;
      _creditId = t.creditAccountId;
      _selectedDate = t.date;
    }
  }

  void _showTemplates() async {
    HapticFeedback.lightImpact();
    final templates = await widget.db.getAllTemplates();
    if (!mounted) return;

    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('テンプレートがありません。設定から登録してください。')));
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('よく使う取引を選択', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: templates.length,
                itemBuilder: (context, index) {
                  final t = templates[index];
                  // ★修正箇所1: ダミーAccountに costType: 'variable' を追加
                  final debitName = widget.accounts.firstWhere((a) => a.id == t.debitAccountId, orElse: () => const Account(id: -1, name: '?', type: '', costType: 'variable')).name;
                  final creditName = widget.accounts.firstWhere((a) => a.id == t.creditAccountId, orElse: () => const Account(id: -1, name: '?', type: '', costType: 'variable')).name;
                  
                  return ListTile(
                    leading: Icon(Icons.bookmark, color: Theme.of(context).colorScheme.primary),
                    title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('$debitName ← $creditName'),
                    trailing: Text('${NumberFormat("#,###").format(t.amount)} 円'),
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      setState(() {
                        _debitId = t.debitAccountId;
                        _creditId = t.creditAccountId;
                        _amountController.text = t.amount.toString();
                      });
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t.name} をセットしました')));
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEditMode = widget.transaction != null; // 編集モードかどうか

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditMode ? '取引の編集' : '記帳'),
        actions: [
           TextButton.icon(
             onPressed: _showTemplates,
             icon: const Icon(Icons.bookmark_outline),
             label: const Text('テンプレート'),
           ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // 日付選択
            GestureDetector(
              onTap: () async {
                HapticFeedback.lightImpact();
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (date != null) setState(() => _selectedDate = date);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('yyyy/MM/dd (E)', 'ja').format(_selectedDate), 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.onSurfaceVariant)
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 30),

            // 金額入力
            Text('いくら？', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              autofocus: !isEditMode, // 編集時はフォーカスしない
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: colorScheme.primary),
              decoration: const InputDecoration(
                hintText: '0', 
                suffixText: '円', // ★修正箇所2: 「円」を表示
                suffixStyle: TextStyle(fontSize: 20, color: Colors.grey),
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.white24), 
              ),
            ),

            const SizedBox(height: 30),

            // 左右カード
            Card(
              elevation: 4,
              shadowColor: colorScheme.shadow.withValues(alpha: 0.2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              color: colorScheme.surfaceContainerLow, 
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text('何に使った？', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                          Text('(借方)', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 10),
                          _buildAccountSelector(_debitId, (val) => setState(() => _debitId = val)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 30),
                      child: Icon(Icons.arrow_back, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text('どう払った？', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                          Text('(貸方)', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 10),
                          _buildAccountSelector(_creditId, (val) => setState(() => _creditId = val)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),

            // 保存ボタン
            SizedBox(
              width: double.infinity,
              height: 60,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                ),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  final amount = int.tryParse(_amountController.text);
                  if (amount != null && _debitId != null && _creditId != null) {
                    final result = {
                      'debitId': _debitId, 
                      'creditId': _creditId, 
                      'amount': amount, 
                      'date': _selectedDate
                    };
                    if (isEditMode) {
                      result['id'] = widget.transaction!.id;
                    }
                    Navigator.of(context).pop(result);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('金額と科目を入力してください')));
                  }
                },
                child: Text(isEditMode ? '更新する' : '記帳する', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSelector(int? value, ValueChanged<int?> onChanged) {
    final colorScheme = Theme.of(context).colorScheme;
    
    // ★修正箇所3: ここでも costType: 'variable' を追加してエラー回避
    final selectedAccount = value != null 
        ? widget.accounts.firstWhere((a) => a.id == value, orElse: () => const Account(id: -1, name: '', type: '', costType: 'variable')) 
        : null;

    IconData icon;
    Color color;
    if (selectedAccount != null) {
        switch (selectedAccount.type) {
            case 'asset': icon = Icons.account_balance_wallet; color = Colors.blue; break;
            case 'income': icon = Icons.savings; color = Colors.green; break;
            case 'liability': icon = Icons.credit_card; color = Colors.orange; break;
            default: icon = Icons.shopping_bag; color = Colors.redAccent;
        }
    } else {
        icon = Icons.add_circle_outline;
        color = colorScheme.onSurfaceVariant;
    }

    return GestureDetector(
      onTap: () async { },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: value != null ? color.withValues(alpha: 0.1) : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: value != null ? color : Colors.transparent, width: 2),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: value,
            isExpanded: true,
            isDense: false,
            icon: Icon(Icons.arrow_drop_down, color: colorScheme.onSurface),
            hint: Center(child: Text('選択', style: TextStyle(color: colorScheme.onSurfaceVariant))),
            alignment: Alignment.center,
            style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16),
            dropdownColor: colorScheme.surfaceContainer,
            items: widget.accounts.map((account) {
              return DropdownMenuItem(
                value: account.id,
                child: Center(
                  child: Text(
                    account.name, 
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}