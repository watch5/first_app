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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.library_books, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'まだ取引がありません\n右下のボタンから記帳してみましょう',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

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
        final dateStr = DateFormat('MM/dd (E)', 'ja').format(date);
        final dayTotal = transactions
            .where((t) => 
                t.date.year == date.year && 
                t.date.month == date.month && 
                t.date.day == date.day)
            .fold(0, (sum, t) => sum + t.amount);

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dateStr, 
                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.secondary, fontSize: 14)
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '計 ${formatter.format(dayTotal)}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)
                ),
              ),
            ],
          ),
        );
      },
      
      // 取引カード
      itemBuilder: (context, t) {
        final debit = accounts.firstWhere((a) => a.id == t.debitAccountId, orElse: () => const Account(id: -1, name: '不明', type: '', costType: 'variable'));
        final credit = accounts.firstWhere((a) => a.id == t.creditAccountId, orElse: () => const Account(id: -1, name: '不明', type: '', costType: 'variable'));

        // 取引タイプに応じた色設定
        Color amountColor;
        IconData icon;
        Color iconBgColor;

        if (debit.type == 'expense') {
          amountColor = Colors.redAccent;
          icon = Icons.shopping_bag_outlined;
          iconBgColor = Colors.red.withValues(alpha: 0.1);
        } else if (credit.type == 'income') {
          amountColor = Colors.green;
          icon = Icons.savings_outlined;
          iconBgColor = Colors.green.withValues(alpha: 0.1);
        } else {
          amountColor = isDark ? Colors.white70 : Colors.black87;
          icon = Icons.swap_horiz;
          iconBgColor = Colors.grey.withValues(alpha: 0.1);
        }

        // ★スワイプ削除機能 (Dismissible)
        return Dismissible(
          key: Key(t.id.toString()),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Colors.redAccent,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('削除', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                SizedBox(width: 8),
                Icon(Icons.delete, color: Colors.white),
              ],
            ),
          ),
          confirmDismiss: (direction) async {
            return await showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('削除しますか？'),
                content: const Text('この操作は元に戻せません。'),
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
          },
          onDismissed: (direction) {
            onDelete(t.id);
          },
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            elevation: 0,
            color: colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onEdit(t),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // アイコン
                    Container(
                      width: 44, 
                      height: 44,
                      decoration: BoxDecoration(
                        color: iconBgColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: amountColor, size: 22),
                    ),
                    const SizedBox(width: 12),

                    // 中央情報
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(debit.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              if (t.isAuto == 1) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.autorenew, size: 14, color: colorScheme.primary.withValues(alpha: 0.7)),
                              ],
                            ],
                          ),
                          Text(
                            '${credit.name}より${t.note != null && t.note!.isNotEmpty ? " / ${t.note}" : ""}', 
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // 金額
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatter.format(t.amount),
                          style: TextStyle(
                            fontSize: 16, 
                            fontWeight: FontWeight.bold,
                            color: amountColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      
      useStickyGroupSeparators: false, // フローティングヘッダーをオフにしてスッキリさせる
    );
  }
}