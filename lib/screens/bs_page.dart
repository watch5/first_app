import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database.dart';
import '../widgets/t_account_table.dart';

class BSPage extends StatefulWidget {
  final List<Transaction> transactions;
  final List<Account> accounts;
  // DBへのアクセスが必要になったので、コールバックかDBインスタンスを受け取る必要がある
  // 今回は簡易的に親(MainScreen)で再ロードをかけるため、ここでの変更はローカルには反映されにくい構造ですが
  // ★重要: ここでは単純化のため、「DB操作はMainScreenの更新を待つ」形にします。
  // 本来は Provider などを使うべきですが、今回はコンストラクタに追加しません（既存の構造維持のため）。
  // 代わりに Navigator.push で戻り値を返すか、簡易的な方法をとります。
  // ...いや、ちゃんと動かすために、DB操作用のコールバックを渡す設計に変えるのがベストですが、
  // MainScreenで addTransaction メソッドを持っているので、それを利用する形にはできません。
  // database.dart のシングルトンや直接インスタンス化を利用します。
  const BSPage({super.key, required this.transactions, required this.accounts});

  @override
  State<BSPage> createState() => _BSPageState();
}

class _BSPageState extends State<BSPage> {
  DateTime _targetDate = DateTime.now();
  bool _isTableView = false; 

  // ★追加: 残高調整ダイアログ
  void _showAdjustmentDialog(String accountName, int currentBalance) async {
    final balanceController = TextEditingController(text: currentBalance.toString());
    
    // アカウントIDを特定
    final account = widget.accounts.firstWhere((a) => a.name == accountName);
    
    // DB操作用にMyDatabaseを一時的に作成（シングルトンではないが、SQLiteはこれで動く）
    // ※ 本来は親から受け取るべきです
    final db = MyDatabase(); 

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$accountName の残高修正'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('実際の手持ち金額を入力してください。\n差額を自動で「残高調整」として記録します。', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
              controller: balanceController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(labelText: '実際の残高', suffixText: '円'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () async {
              HapticFeedback.mediumImpact();
              final newBalance = int.tryParse(balanceController.text);
              if (newBalance != null) {
                // 差額計算
                final diff = newBalance - currentBalance;
                if (diff != 0) {
                   // 残高調整アカウント取得
                   final accounts = await db.getAllAccounts();
                   Account? adjAccount;
                   try { adjAccount = accounts.firstWhere((a) => a.name == '残高調整'); } 
                   catch (e) { await db.addAccount('残高調整', 'expense', null); final newAccs = await db.getAllAccounts(); adjAccount = newAccs.firstWhere((a) => a.name == '残高調整'); }

                   if (diff > 0) {
                     await db.addTransaction(account.id, adjAccount!.id, diff, DateTime.now());
                   } else {
                     await db.addTransaction(adjAccount!.id, account.id, diff.abs(), DateTime.now());
                   }
                   
                   if (mounted) {
                     Navigator.pop(ctx, true); // 変更があったことを伝える
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('残高を調整しました')));
                   }
                } else {
                   Navigator.pop(ctx);
                }
              }
            },
            child: const Text('修正実行'),
          ),
        ],
      ),
    );
    // ※ここで画面更新を呼び出したいが、MainScreenが管理しているため、
    // ユーザーが「記帳」ボタンなどを押したタイミングやタブ切り替えで更新されるのを待つ形になります。
    // 即時反映させるにはState管理の導入(Riverpod等)が推奨されます。
  }

  @override
  Widget build(BuildContext context) {
    int totalAsset = 0;
    int totalLiability = 0;
    Map<String, int> assetMap = {};
    Map<String, int> liabilityMap = {};

    for (var account in widget.accounts) {
      if (account.type == 'asset') assetMap[account.name] = 0;
      else if (account.type == 'liability') liabilityMap[account.name] = 0;
    }

    final endOfTargetDate = DateTime(_targetDate.year, _targetDate.month, _targetDate.day).add(const Duration(days: 1));

    for (var a in widget.accounts) {
      if (a.type != 'asset' && a.type != 'liability') continue;
      int balance = 0;
      for (var t in widget.transactions) {
        if (t.date.isBefore(endOfTargetDate)) {
          if (t.debitAccountId == a.id) balance += t.amount;
          if (t.creditAccountId == a.id) balance -= t.amount;
        }
      }
      if (a.type == 'asset') { totalAsset += balance; assetMap[a.name] = balance; } 
      else if (a.type == 'liability') { totalLiability += balance; liabilityMap[a.name] = balance; }
    }

    final netAssets = totalAsset - totalLiability;
    final fmt = NumberFormat("#,###");

    final assetList = assetMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final liabilityList = liabilityMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    liabilityList.add(MapEntry('純資産', netAssets));
    
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 日付選択
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () async {
                  HapticFeedback.lightImpact();
                  final date = await showDatePicker(context: context, initialDate: _targetDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                  if (date != null) setState(() => _targetDate = date);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today, size: 20, color: colorScheme.primary),
                      const SizedBox(width: 10),
                      Text('${DateFormat('yyyy/MM/dd').format(_targetDate)} 時点', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.onSurface)),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: () { HapticFeedback.selectionClick(); setState(() => _isTableView = !_isTableView); },
                icon: Icon(_isTableView ? Icons.pie_chart : Icons.description),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_isTableView) ...[
            TAccountTable(
              title: '貸借対照表 (B/S)',
              headerColor: Colors.indigo,
              leftItems: assetList,
              rightItems: liabilityList,
              leftTotal: totalAsset,
              rightTotal: totalAsset,
            ),
          ] else ...[
            // 純資産カード
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.indigo, Colors.blue]), borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                const Text('純資産', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 5),
                Text('¥${fmt.format(netAssets)}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
              ]),
            ),
            const SizedBox(height: 30),
            
            // 円グラフ
            if (totalAsset > 0)
              SizedBox(
                height: 200,
                child: PieChart(PieChartData(
                  sections: assetMap.entries.map((e) {
                    final isLarge = e.value / totalAsset > 0.1;
                    return PieChartSectionData(
                      color: Colors.primaries[e.key.hashCode % Colors.primaries.length],
                      value: e.value.toDouble(),
                      title: isLarge ? '${(e.value / totalAsset * 100).toStringAsFixed(0)}%' : '',
                      radius: 50,
                      titleStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                    );
                  }).toList(),
                )),
              ),
            const SizedBox(height: 20),
            
            // 資産リスト（★タップで修正できるように変更）
            Align(alignment: Alignment.centerLeft, child: Text('資産の内訳', style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface))),
            const SizedBox(height: 10),
            ...assetMap.entries.map((e) {
              return Card(
                elevation: 0,
                color: colorScheme.surfaceContainer,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile( // ListTile自体がタップ機能を持つ
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.account_balance_wallet, color: Colors.blue),
                  ),
                  title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('¥${fmt.format(e.value)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(width: 8),
                      Icon(Icons.edit, size: 14, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    ],
                  ),
                  onTap: () => _showAdjustmentDialog(e.key, e.value), // ★タップでダイアログ表示
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}