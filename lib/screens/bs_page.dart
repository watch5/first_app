import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database.dart';
import '../widgets/t_account_table.dart';
import 'pet_room_page.dart';

class BSPage extends StatefulWidget {
  final List<Transaction> transactions;
  final List<Account> accounts;
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
  bool _isTableView = false; 

  Future<void> _showAdjustBalanceDialog() async {
    // (既存の調整ロジックはそのまま維持)
    final assetAccounts = widget.accounts.where((a) => a.type == 'asset').toList();
    if (assetAccounts.isEmpty) return;
    Account selectedAccount = assetAccounts.first;
    final amountController = TextEditingController();
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
                const Text('「実際の残高」を入力してください。差額を自動調整します。', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 20),
                DropdownButtonFormField<Account>(
                  initialValue: selectedAccount,
                  decoration: const InputDecoration(labelText: '合わせる口座'),
                  items: assetAccounts.map((a) => DropdownMenuItem(value: a, child: Text(a.name))).toList(),
                  onChanged: (val) { if (val != null) setState(() { selectedAccount = val; amountController.clear(); }); },
                ),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: '実際いくらある？', hintText: '現在の残高', suffixText: '円', helperText: '帳簿: ${NumberFormat("#,###").format(currentBookBalance)}円'),
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
                  if (diff == 0) { Navigator.pop(ctx); return; }
                  
                  Account? adjAccount;
                  try { adjAccount = widget.accounts.firstWhere((a) => a.name == '使途不明金' || a.name == '残高調整'); } 
                  catch (e) { await widget.db.addAccount('使途不明金', 'expense', null, 'variable'); final newAccounts = await widget.db.getAllAccounts(); adjAccount = newAccounts.firstWhere((a) => a.name == '使途不明金'); }

                  if (diff > 0) await widget.db.addTransaction(selectedAccount.id, adjAccount!.id, diff, DateTime.now(), isAuto: true);
                  else await widget.db.addTransaction(adjAccount!.id, selectedAccount.id, diff.abs(), DateTime.now(), isAuto: true);

                  if (context.mounted) { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${diff.abs()}円のズレを調整しました'))); widget.onDataChanged(); }
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

    Map<int, int> balances = {};
    for (var a in widget.accounts) balances[a.id] = 0;
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
      if (a.type == 'asset') { assetsList.add(MapEntry(a.name, amount)); totalAssets += amount; } 
      else if (a.type == 'liability') { liabilitiesList.add(MapEntry(a.name, -amount)); totalLiabilities += -amount; }
    }

    final netAssets = totalAssets - totalLiabilities;
    liabilitiesList.add(MapEntry('純資産', netAssets));
    assetsList.sort((a, b) => b.value.compareTo(a.value));
    liabilitiesList.sort((a, b) => b.value.compareTo(a.value));

    // 自己資本比率
    double equityRatio = totalAssets > 0 ? (netAssets / totalAssets * 100) : 0;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('財政状態 (B/S)'),
            floating: true,
            actions: [
              IconButton.filledTonal(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => PetRoomPage(db: widget.db))), icon: const Icon(Icons.pets, color: Colors.indigo)),
              const SizedBox(width: 8),
              IconButton.filledTonal(onPressed: () => setState(() => _isTableView = !_isTableView), icon: Icon(_isTableView ? Icons.pie_chart : Icons.description)),
              const SizedBox(width: 8),
            ],
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              if (_isTableView) ...[
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TAccountTable(title: '貸借対照表 (B/S)', headerColor: Colors.indigo, leftItems: assetsList, rightItems: liabilitiesList, leftTotal: totalAssets, rightTotal: totalLiabilities + netAssets),
                ),
              ] else ...[
                // 1. 純資産カード
                _buildNetWorthCard(context, netAssets, equityRatio, totalAssets, totalLiabilities, fmt),

                // 2. 資産構成グラフ (PieChart)
                if (totalAssets > 0)
                  SizedBox(
                    height: 250,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: 40,
                            sections: _buildPieSections(assetsList, totalAssets),
                          ),
                        ),
                        const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.account_balance_wallet, color: Colors.grey),
                            Text("資産内訳", style: TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        )
                      ],
                    ),
                  ),

                // 3. 資産・負債バランスバー
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('総資産: ¥${fmt.format(totalAssets)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('負債: ¥${fmt.format(totalLiabilities)}', style: const TextStyle(color: Colors.red)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: totalAssets > 0 ? (totalLiabilities / totalAssets).clamp(0.0, 1.0) : 0,
                          backgroundColor: Colors.blueAccent,
                          color: Colors.redAccent,
                          minHeight: 12,
                        ),
                      ),
                      const Align(alignment: Alignment.centerRight, child: Text('赤色: 負債比率', style: TextStyle(fontSize: 10, color: Colors.grey))),
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                // 4. 残高調整ボタン
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    onPressed: _showAdjustBalanceDialog,
                    icon: const Icon(Icons.build_circle_outlined),
                    label: const Text('残高が合わない時はこちら (調整)'),
                  ),
                ),
                const SizedBox(height: 20),

                // 5. 資産リスト詳細
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: const Text('資産リスト', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                ...assetsList.map((e) => _buildAssetTile(e, totalAssets, fmt)),
                const SizedBox(height: 40),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildNetWorthCard(BuildContext context, int netWorth, double equityRatio, int assets, int liabilities, NumberFormat fmt) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade800, Colors.indigo.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.indigo.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Column(
        children: [
          const Text('純資産 (Net Worth)', style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text('¥ ${fmt.format(netWorth)}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(children: [
                const Text('自己資本比率', style: TextStyle(color: Colors.white70, fontSize: 11)),
                Text('${equityRatio.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
              Container(width: 1, height: 30, color: Colors.white24),
              Column(children: [
                const Text('負債比率', style: TextStyle(color: Colors.white70, fontSize: 11)),
                Text('${(100 - equityRatio).toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ]),
            ],
          ),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildPieSections(List<MapEntry<String, int>> items, int total) {
    // 上位5件 + その他
    if (total == 0) return [];
    List<Color> colors = [Colors.blue, Colors.teal, Colors.amber, Colors.orange, Colors.purple, Colors.grey];
    
    return List.generate(items.length, (i) {
      final isLarge = i < 5;
      final value = items[i].value.toDouble();
      final percent = (value / total * 100);
      
      return PieChartSectionData(
        color: colors[i % colors.length],
        value: value,
        title: isLarge && percent > 5 ? '${percent.toStringAsFixed(0)}%' : '',
        radius: isLarge ? 50 : 40,
        titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
      );
    });
  }

  Widget _buildAssetTile(MapEntry<String, int> item, int total, NumberFormat fmt) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
        child: const Icon(Icons.account_balance_wallet, color: Colors.blue, size: 20),
      ),
      title: Text(item.key),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('¥${fmt.format(item.value)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${(item.value / total * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}