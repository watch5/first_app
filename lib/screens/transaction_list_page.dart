import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:grouped_list/grouped_list.dart'; // ★追加: これがグループ化の主役
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
      return const Center(child: Text('まだ取引がありません\n右下のボタンから記帳してみましょう', textAlign: TextAlign.center));
    }

    final formatter = NumberFormat("#,###");
    final colorScheme = Theme.of(context).colorScheme;

    // ★ GroupedListView を使うのがポイント！
    return GroupedListView<Transaction, DateTime>(
      elements: transactions,
      
      // グループ化の基準（日付の「年月日」が同じならまとめる）
      groupBy: (transaction) {
        final date = transaction.date;
        return DateTime(date.year, date.month, date.day); 
      },
      
      // リストの並び順（日付の新しい順）
      order: GroupedListOrder.DESC, 

      // ★ヘッダーのデザイン（日付の帯）
      groupSeparatorBuilder: (DateTime date) {
        final dateStr = DateFormat('yyyy/MM/dd (E)', 'ja').format(date);
        
        // その日の合計金額を計算する（ちょっとしたこだわり機能）
        final dayTotal = transactions
            .where((t) => 
                t.date.year == date.year && 
                t.date.month == date.month && 
                t.date.day == date.day)
            .fold(0, (sum, t) => sum + t.amount);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: colorScheme.surfaceContainerHighest.withOpacity(0.5), // 薄い背景色
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dateStr, 
                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)
              ),
              Text(
                '計 ${formatter.format(dayTotal)}円', 
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)
              ),
            ],
          ),
        );
      },
      
      // ★中身のデザイン（取引カード）
      itemBuilder: (context, t) {
        // IDから勘定科目名を探す
        final debitName = accounts.firstWhere((a) => a.id == t.debitAccountId, orElse: () => const Account(id: -1, name: '不明', type: '', costType: 'variable')).name;
        final creditName = accounts.firstWhere((a) => a.id == t.creditAccountId, orElse: () => const Account(id: -1, name: '不明', type: '', costType: 'variable')).name;

        return Card(
          elevation: 0,
          color: colorScheme.surface, // 背景はシンプルに
          margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0), // 隙間をなくしてリストっぽく
          shape: Border(bottom: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.2))), // 下線だけ引く
          child: InkWell(
            onTap: () => onEdit(t),
            onLongPress: () {
               HapticFeedback.heavyImpact();
               _showDeleteDialog(context, t, formatter);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // 左：科目
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(debitName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.payment, size: 12, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(creditName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 右：金額
                  Text(
                    '¥ ${formatter.format(t.amount)}',
                    style: TextStyle(
                      fontSize: 18, 
                      fontWeight: FontWeight.bold,
                      // 収益(income)の科目が借方にある場合は青、それ以外（費用など）は通常色などの色分けも可能ですが、
                      // 一旦シンプルにプライマリーカラーにします
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
      
      // ヘッダーを上に吸着させる設定（これが見やすさの秘密！）
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
        content: Text('$dateStr の取引\n${formatter.format(t.amount)}円 を削除します。'),
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