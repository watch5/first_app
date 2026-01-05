import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database.dart'; 

class TransactionListScreen extends StatelessWidget {
  final List<Transaction> transactions;
  final List<Account> accounts;
  final Function(int) onDelete;
  final Function(Transaction) onEdit; // これが定義されているか確認

  const TransactionListScreen({
    super.key,
    required this.transactions,
    required this.accounts,
    required this.onDelete,
    required this.onEdit,
  });

  String _getAccountName(int id) => 
      accounts.firstWhere((a) => a.id == id, orElse: () => const Account(id: -1, name: '?', type: '', monthlyBudget: null, costType: 'variable')).name;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) return const Center(child: Text('データがありません'));
    
    final colorScheme = Theme.of(context).colorScheme;
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: transactions.length,
      itemBuilder: (context, index) {
        final t = transactions[index];
        final debitName = _getAccountName(t.debitAccountId);
        final creditName = _getAccountName(t.creditAccountId);
        final fmt = NumberFormat("#,###");

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Row(
              children: [
                Text(debitName, style: const TextStyle(fontWeight: FontWeight.bold)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_back, size: 16, color: Colors.grey),
                ),
                Text(creditName, style: const TextStyle(color: Colors.grey)),
              ],
            ),
            subtitle: Text(DateFormat('yyyy/MM/dd').format(t.date)),
            trailing: Text(
              '${fmt.format(t.amount)} 円',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.primary),
            ),
            onTap: () {
              HapticFeedback.lightImpact();
              onEdit(t);
            },
            onLongPress: () {
               HapticFeedback.heavyImpact();
               onDelete(t.id);
            },
          ),
        );
      },
    );
  }
}