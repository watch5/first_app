import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database.dart';
import '../widgets/t_account_table.dart';

class BSPage extends StatefulWidget {
  final List<Transaction> transactions;
  final List<Account> accounts;
  // ★追加: DB操作と画面更新のために必要
  final MyDatabase db;
  final Function onDataChanged;

  const BSPage({
    super.key,
    required this.transactions,
    required this.accounts,
    required this.db,
    required this.onDataChanged,
  });

  @override
  State<BSPage> createState() => _BSPageState();
}

class _BSPageState extends State<BSPage> {
  bool _isTableView = false; // 表モードかどうかのフラグ

  // ★追加: 残高合わせダイアログ
  Future<void> _showAdjustBalanceDialog() async {
    // 資産口座だけを抽出
    final assetAccounts = widget.accounts.where((a) => a.type == 'asset').toList();
    if (assetAccounts.isEmpty) return;

    Account selectedAccount = assetAccounts.first;
    final amountController = TextEditingController();

    // 現在の計算上の残高を取得する関数
    int getCurrentBookBalance(int accountId) {
      int balance = 0;
      for (var t in widget.transactions) {
        if (t.debitAccountId == accountId) balance += t.amount;
        if (t.creditAccountId == accountId) balance -= t.amount;
      }
      return balance;
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final currentBookBalance = getCurrentBookBalance(selectedAccount.id);
          
          return AlertDialog(
            title: const Text('残高合わせ（ズレ補正）'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('「実際の残高」を入力してください。\n計算上の残高との差額を「使途不明金」として自動調整します。', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 20),
                DropdownButtonFormField<Account>(
                  initialValue: selectedAccount,
                  decoration: const InputDecoration(labelText: '合わせる口座'),
                  items: assetAccounts.map((a) => DropdownMenuItem(value: a, child: Text(a.name))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        selectedAccount = val;
                        amountController.clear(); // 口座を変えたらクリア
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '実際いくらある？',
                    hintText: '現在の${selectedAccount.name}の残高',
                    suffixText: '円',
                    helperText: 'アプリ上の計算: ${NumberFormat("#,###").format(currentBookBalance)}円',
                  ),
                  autofocus: true,
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
              FilledButton(
                onPressed: () async {
                  final actualBalance = int.tryParse(amountController.text);
                  if (actualBalance == null) return;

                  final diff = actualBalance - currentBookBalance;
                  if (diff == 0) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ズレはありませんでした！完璧です✨')));
                    return;
                  }

                  HapticFeedback.mediumImpact();
                  
                  // 調整用科目の取得（なければ作成）
                  Account? adjAccount;
                  try {
                    adjAccount = widget.accounts.firstWhere((a) => a.name == '使途不明金' || a.name == '残高調整');
                  } catch (e) {
                    await widget.db.addAccount('使途不明金', 'expense', null, 'variable');
                    // リロードしないとIDが取れないので簡易的に名前で再取得...はできないので、
                    // ここではメイン画面のリロードを呼んでから処理を終了させたいが、
                    // 複雑になるので「調整用科目を作りました。もう一度実行してください」とするか、
                    // あるいはここで再度DBから引く。今回は簡易的に再度DBから引きます。
                    final newAccounts = await widget.db.getAllAccounts();
                    adjAccount = newAccounts.firstWhere((a) => a.name == '使途不明金');
                  }

                  // 記帳実行
                  if (diff > 0) {
                    // 実際の方が多い＝臨時収入（または記入漏れの入金）
                    // 借方:資産 / 貸方:不明金
                    // ★isAuto: true にしておくと、あとで「これは自動調整だ」と分かって便利
                    await widget.db.addTransaction(selectedAccount.id, adjAccount.id, diff, DateTime.now(), isAuto: true);
                  } else {
                    // 実際の方が少ない＝使途不明金（支出）
                    // 借方:不明金 / 貸方:資産
                    await widget.db.addTransaction(adjAccount.id, selectedAccount.id, diff.abs(), DateTime.now(), isAuto: true);
                  }

                  if (context.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${diff.abs()}円のズレを調整しました')));
                    widget.onDataChanged(); // 親画面を更新
                  }
                },
                child: const Text('調整実行'),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat("#,###");
    final colorScheme = Theme.of(context).colorScheme;

    // --- 集計ロジック (全期間の積み上げ) ---
    Map<int, int> balances = {};
    for (var a in widget.accounts) {
      balances[a.id] = 0;
    }

    for (var t in widget.transactions) {
      balances[t.debitAccountId] = (balances[t.debitAccountId] ?? 0) + t.amount;
      balances[t.creditAccountId] = (balances[t.creditAccountId] ?? 0) - t.amount;
    }

    List<MapEntry<String, int>> assetsList = [];
    List<MapEntry<String, int>> liabilitiesList = [];
    
    int totalAssets = 0;
    int totalLiabilities = 0;

    for (var a in widget.accounts) {
      final amount = balances[a.id] ?? 0;
      if (amount == 0) continue;

      if (a.type == 'asset') {
        assetsList.add(MapEntry(a.name, amount));
        totalAssets += amount;
      } else if (a.type == 'liability') {
        liabilitiesList.add(MapEntry(a.name, -amount));
        totalLiabilities += -amount;
      }
    }

    final netAssets = totalAssets - totalLiabilities;
    liabilitiesList.add(MapEntry('純資産', netAssets));

    // 金額順にソート
    assetsList.sort((a, b) => b.value.compareTo(a.value));
    liabilitiesList.sort((a, b) => b.value.compareTo(a.value));

    // --- 画面構築 ---
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ヘッダー (タイトル + 切り替えボタン)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('現在の資産状況', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton.filledTonal(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isTableView = !_isTableView);
                },
                icon: Icon(_isTableView ? Icons.pie_chart : Icons.description),
                tooltip: _isTableView ? 'グラフに戻る' : '貸借対照表を見る',
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ★追加: 残高合わせボタン
          if (!_isTableView)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showAdjustBalanceDialog,
                icon: const Icon(Icons.build_circle_outlined),
                label: const Text('財布の中身が合わない時はこちら (残高調整)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: colorScheme.primary.withOpacity(0.5)),
                ),
              ),
            ),

          // 切り替えロジック
          if (_isTableView) ...[
            // === T字勘定モード ===
            TAccountTable(
              title: '貸借対照表 (B/S)',
              headerColor: Colors.indigo,
              leftItems: assetsList,
              rightItems: liabilitiesList,
              leftTotal: totalAssets,
              rightTotal: totalLiabilities + netAssets,
            ),
          ] else ...[
            // === サマリー＆グラフモード ===
            
            // 1. 純資産カード
            Card(
              elevation: 4,
              shadowColor: colorScheme.shadow.withOpacity(0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              color: colorScheme.surfaceContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text('純資産 (あなたの本当の財産)', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
                    const SizedBox(height: 5),
                    Text(
                      '${fmt.format(netAssets)} 円',
                      style: TextStyle(
                        fontSize: 32, 
                        fontWeight: FontWeight.bold,
                        color: netAssets >= 0 ? colorScheme.primary : colorScheme.error,
                      ),
                    ),
                    const Divider(height: 30),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryItem('総資産', totalAssets, Colors.blue),
                        Container(width: 1, height: 40, color: colorScheme.outlineVariant),
                        _buildSummaryItem('負債', totalLiabilities, Colors.orange),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),

            // 2. 簡易グラフ (資産 vs 負債)
            if (totalAssets > 0)
              SizedBox(
                height: 30,
                child: Row(
                  children: [
                    Expanded(
                      flex: totalAssets > 0 ? totalAssets : 1,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.horizontal(left: Radius.circular(8)),
                        ),
                        alignment: Alignment.center,
                        child: const Text('資産', style: TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                    ),
                    if (totalLiabilities > 0)
                      Expanded(
                        flex: totalLiabilities,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.horizontal(right: Radius.circular(8)),
                          ),
                          alignment: Alignment.center,
                          child: const Text('負債', style: TextStyle(color: Colors.white, fontSize: 10)),
                        ),
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 20),
            Align(alignment: Alignment.centerLeft, child: Text('資産の内訳', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface))),
            const SizedBox(height: 10),

            // 3. 資産リスト
            ...assetsList.map((e) {
              final percent = totalAssets > 0 ? (e.value / totalAssets) : 0.0;
              return Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.account_balance_wallet, color: Colors.white, size: 18)),
                  title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${fmt.format(e.value)} 円', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('${(percent * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String title, int amount, Color color) {
    final fmt = NumberFormat("#,###");
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          fmt.format(amount), 
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}