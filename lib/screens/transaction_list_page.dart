import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart'; // ★追加：これでカンマ表示ができるようになります
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

    // ★追加：カンマ区切りのフォーマッターを作成
    final formatter = NumberFormat("#,###");

    return ListView.builder(
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final t = transactions[index];
        
        // IDから勘定科目名を探す（見つからない場合は「不明」）
        final debitName = accounts.firstWhere((a) => a.id == t.debitAccountId, orElse: () => const Account(id: -1, name: '不明', type: '', costType: 'variable')).name;
        final creditName = accounts.firstWhere((a) => a.id == t.creditAccountId, orElse: () => const Account(id: -1, name: '不明', type: '', costType: 'variable')).name;

        // 日付のフォーマット
        final dateStr = DateFormat('yyyy/MM/dd').format(t.date);

        return Card(
          elevation: 0, // フラットなデザイン
          color: Theme.of(context).colorScheme.surfaceContainer, // 背景色を薄く
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: ListTile(
            // 左側に日付
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(DateFormat('MM/dd').format(t.date), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(DateFormat('E', 'ja').format(t.date), style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
            
            // 中央に科目（借方 ← 貸方）
            title: Row(
              children: [
                Text(debitName, style: const TextStyle(fontWeight: FontWeight.bold)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: Icon(Icons.arrow_left, size: 16, color: Colors.grey),
                ),
                Text(creditName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            
            // ★修正箇所：ここでformatterを使ってカンマ区切りにする！
            trailing: Text(
              '${formatter.format(t.amount)} 円',
              style: TextStyle(
                fontSize: 18, 
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            
            onTap: () => onEdit(t),
            onLongPress: () {
               HapticFeedback.heavyImpact();
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
            },
          ),
        );
      },
    );
  }
}