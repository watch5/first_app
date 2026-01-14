import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:grouped_list/grouped_list.dart';
import 'dart:ui'; // FontFeature用
import '../database.dart';

class TransactionListScreen extends StatelessWidget {
  final List<Transaction> transactions;
  final List<Account> accounts;
  final Function(int) onDelete;
  final Function(Transaction) onEdit;

  const TransactionListScreen({
    super.key,
    required this.transactions,
    required this.accounts,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return const Center(
        child: Text(
          'まだ取引がありません\n右下のボタンから記帳してみましょう',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // ★修正: decimalDigits: 0 で小数点を確実に非表示にする
    final formatter = NumberFormat.currency(locale: 'ja', symbol: '¥', decimalDigits: 0);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GroupedListView<Transaction, DateTime>(
      elements: transactions,
      
      // グループ化の基準（日付）
      groupBy: (transaction) {
        final date = transaction.date;
        return DateTime(date.year, date.month, date.day); 
      },
      
      // 並び順（新しい順）
      order: GroupedListOrder.DESC, 

      // ヘッダー（日付帯）
      groupSeparatorBuilder: (DateTime date) {
        final dateStr = DateFormat('yyyy/MM/dd (E)', 'ja').format(date);
        
        final dayTotal = transactions
            .where((t) => 
                t.date.year == date.year && 
                t.date.month == date.month && 
                t.date.day == date.day)
            .fold(0, (sum, t) => sum + t.amount);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? colorScheme.surfaceContainerHighest : colorScheme.surfaceVariant.withOpacity(0.5),
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.2))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dateStr, 
                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)
              ),
              Text(
                '計 ${formatter.format(dayTotal)}', // 記号付きフォーマッタを使用
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)
              ),
            ],
          ),
        );
      },
      
      // 取引カード
      itemBuilder: (context, t) {
        final debit = accounts.firstWhere((a) => a.id == t.debitAccountId, orElse: () => const Account(id: -1, name: '不明', type: '', costType: 'variable'));
        final credit = accounts.firstWhere((a) => a.id == t.creditAccountId, orElse: () => const Account(id: -1, name: '不明', type: '', costType: 'variable'));

        // ★視認性向上: 取引タイプに応じた色とアイコン
        Color amountColor;
        IconData icon;
        Color iconBgColor;

        if (debit.type == 'expense') {
          // 支出
          amountColor = Colors.redAccent;
          icon = Icons.shopping_cart_outlined;
          iconBgColor = Colors.redAccent.withOpacity(0.1);
        } else if (credit.type == 'income') {
          // 収入
          amountColor = Colors.green;
          icon = Icons.savings_outlined;
          iconBgColor = Colors.green.withOpacity(0.1);
        } else {
          // 振替など
          amountColor = isDark ? Colors.white70 : Colors.black87;
          icon = Icons.swap_horiz;
          iconBgColor = isDark ? Colors.grey.withOpacity(0.2) : Colors.grey.withOpacity(0.1);
        }

        return Material(
          color: colorScheme.surface,
          child: InkWell(
            onTap: () => onEdit(t),
            onLongPress: () {
               HapticFeedback.heavyImpact();
               _showDeleteDialog(context, t, formatter);
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.2))),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // アイコン
                  Container(
                    width: 40, 
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: amountColor, size: 20),
                  ),
                  const SizedBox(width: 16),

                  // 中央情報（科目名など）
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(debit.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            if (t.isAuto == 1) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.autorenew, size: 14, color: colorScheme.primary.withOpacity(0.7)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text('from ', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                            Text(credit.name, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 金額
                  Text(
                    formatter.format(t.amount),
                    style: TextStyle(
                      fontSize: 17, 
                      fontWeight: FontWeight.bold,
                      color: amountColor,
                      fontFeatures: const [FontFeature.tabularFigures()], // 数字の幅を揃える
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, size: 18, color: Colors.grey.withOpacity(0.3)),
                ],
              ),
            ),
          ),
        );
      },
      
      useStickyGroupSeparators: true, 
      floatingHeader: true,
    );
  }

  void _showDeleteDialog(BuildContext context, Transaction t, NumberFormat formatter) {
    final dateStr = DateFormat('yyyy/MM/dd').format(t.date);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除しますか？'),
        content: Text('$dateStr の取引\n${formatter.format(t.amount)} を削除します。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete(t.id);
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}