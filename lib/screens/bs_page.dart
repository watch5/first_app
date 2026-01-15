import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_generative_ai/google_generative_ai.dart'; // Gemini
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
  // ★ここにAPIキーを入れてください
  final String _apiKey = 'AIzaSyAjn7KgHXI8tx6lHGgmNiD7EsaaxTGWaXA';

  bool _isTableView = false; 
  String? _aiComment;
  bool _isAiLoading = false;

  Future<void> _showAdjustBalanceDialog() async {
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
                const Text('「実際の残高」を入力してください。\n差額を自動で調整します。', style: TextStyle(fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 20),
                DropdownButtonFormField<Account>(
                  initialValue: selectedAccount,
                  decoration: const InputDecoration(labelText: '合わせる口座', border: OutlineInputBorder()),
                  items: assetAccounts.map((a) => DropdownMenuItem(value: a, child: Text(a.name))).toList(),
                  onChanged: (val) { if (val != null) setState(() { selectedAccount = val; amountController.clear(); }); },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '実際の残高', 
                    hintText: '手元にある金額', 
                    suffixText: '円', 
                    border: const OutlineInputBorder(),
                    helperText: '帳簿上の残高: ${NumberFormat("#,###").format(currentBookBalance)}円'
                  ),
                  autofocus: true,
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
              FilledButton.icon(
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
                icon: const Icon(Icons.check),
                label: const Text('調整実行'),
              ),
            ],
          );
        }
      ),
    );
  }

  // ★GeminiでB/S診断
  Future<void> _analyzeWithGemini(int assets, int liabilities, int netAssets, double equityRatio) async {
    setState(() => _isAiLoading = true);

    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey);
      final prompt = """
        あなたはプロのファイナンシャルアドバイザーです。
        以下の個人の貸借対照表（バランスシート）の状態を見て、財務健全性を診断し、アドバイスをください。

        【データ】
        - 総資産: $assets 円
        - 負債（借金など）: $liabilities 円
        - 純資産: $netAssets 円
        - 自己資本比率: ${equityRatio.toStringAsFixed(1)} %

        【ルール】
        - 日本語で140文字以内。
        - 専門用語はなるべく使わず、分かりやすく。
        - 絵文字を使って親しみやすく。
        - 「資産を増やすコツ」や「負債への向き合い方」などを一言添えてください。
      """;

      final response = await model.generateContent([Content.text(prompt)]);
      
      if (mounted) {
        setState(() {
          _aiComment = response.text;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _aiComment = "診断できませんでした...💦");
      }
    } finally {
      if (mounted) {
        setState(() => _isAiLoading = false);
      }
    }
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
          SliverAppBar.large(
            title: const Text('財政状態 (B/S)'),
            actions: [
              IconButton.filledTonal(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => PetRoomPage(db: widget.db))), icon: const Icon(Icons.pets, color: Colors.indigo)),
              const SizedBox(width: 8),
              IconButton.outlined(onPressed: () => setState(() => _isTableView = !_isTableView), icon: Icon(_isTableView ? Icons.pie_chart : Icons.table_chart)),
              const SizedBox(width: 16),
            ],
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              if (_isTableView) ...[
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TAccountTable(title: '貸借対照表 (B/S)', headerColor: Colors.indigo, leftItems: assetsList, rightItems: liabilitiesList, leftTotal: totalAssets, rightTotal: totalLiabilities + netAssets),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _buildNetWorthCard(context, netAssets, equityRatio, totalAssets, totalLiabilities, fmt),
                      const SizedBox(height: 16),

                      // ★AI財務診断カード
                      _buildAiDiagnosisCard(context, totalAssets, totalLiabilities, netAssets, equityRatio),
                      const SizedBox(height: 16),

                      if (totalAssets > 0)
                        Card(
                          elevation: 0,
                          color: colorScheme.surfaceContainer,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: SizedBox(
                              height: 250,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  PieChart(
                                    PieChartData(
                                      sectionsSpace: 4,
                                      centerSpaceRadius: 60,
                                      sections: _buildPieSections(assetsList, totalAssets),
                                      startDegreeOffset: -90,
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text("総資産", style: TextStyle(fontSize: 12, color: Colors.grey)),
                                      Text(
                                        '¥${fmt.format(totalAssets)}',
                                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 16),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          border: Border.all(color: colorScheme.outlineVariant),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.balance, size: 16, color: Colors.grey),
                                const SizedBox(width: 8),
                                const Text('資産バランス', style: TextStyle(fontWeight: FontWeight.bold)),
                                const Spacer(),
                                Text('負債比率 ${(100 - equityRatio).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: Colors.red)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: (netAssets > 0 ? netAssets : 0),
                                    child: Container(height: 20, color: Colors.blueAccent),
                                  ),
                                  Expanded(
                                    flex: totalLiabilities,
                                    child: Container(height: 20, color: Colors.redAccent),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(children: [
                                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle)),
                                  const SizedBox(width: 4),
                                  Text('純資産 ¥${fmt.format(netAssets)}', style: const TextStyle(fontSize: 12)),
                                ]),
                                Row(children: [
                                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
                                  const SizedBox(width: 4),
                                  Text('負債 ¥${fmt.format(totalLiabilities)}', style: const TextStyle(fontSize: 12)),
                                ]),
                              ],
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 32),

                      Align(
                        alignment: Alignment.centerLeft, 
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 8),
                          child: Text('資産の内訳', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                        )
                      ),
                      ...assetsList.map((e) => _buildAssetTile(context, e, totalAssets, fmt)),
                      
                      const SizedBox(height: 24),
                      
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: _showAdjustBalanceDialog,
                          icon: const Icon(Icons.build_circle_outlined),
                          label: const Text('実際の残高と合わない場合はこちら (調整)'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey,
                            padding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildAiDiagnosisCard(BuildContext context, int assets, int liabilities, int netAssets, double equityRatio) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Card(
      elevation: 2,
      shadowColor: Colors.indigo.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.indigo.withOpacity(0.5))),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.health_and_safety, color: Colors.indigo),
                const SizedBox(width: 8),
                Text("AI財務診断", style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                const Spacer(),
                if (_aiComment == null && !_isAiLoading)
                  FilledButton.icon(
                    onPressed: () => _analyzeWithGemini(assets, liabilities, netAssets, equityRatio),
                    icon: const Icon(Icons.analytics, size: 16),
                    label: const Text("診断する"),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isAiLoading)
              const Center(child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(color: Colors.indigo),
              ))
            else if (_aiComment != null)
              AnimatedOpacity(
                opacity: 1.0,
                duration: const Duration(milliseconds: 500),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _aiComment!,
                    style: TextStyle(fontSize: 14, height: 1.5, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              Text("現在の資産状況から、財務の健全性を診断します。", style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  // --- 既存UIパーツ ---
  Widget _buildNetWorthCard(BuildContext context, int netWorth, double equityRatio, int assets, int liabilities, NumberFormat fmt) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade800, Colors.indigo.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.indigo.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          const Text('純資産 (Net Worth)', style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text('¥ ${fmt.format(netWorth)}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Column(children: [
                const Text('自己資本比率', style: TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(height: 4),
                Text('${equityRatio.toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ]),
              Container(width: 1, height: 30, color: Colors.white24),
              Column(children: [
                const Text('総資産', style: TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(height: 4),
                Text('¥${fmt.format(assets)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ]),
            ],
          ),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildPieSections(List<MapEntry<String, int>> items, int total) {
    if (total == 0) return [];
    List<Color> colors = [Colors.blue, Colors.cyan, Colors.teal, Colors.green, Colors.lightGreen, Colors.grey];
    
    return List.generate(items.length, (i) {
      final isLarge = i < 5;
      final value = items[i].value.toDouble();
      final percent = (value / total * 100);
      
      return PieChartSectionData(
        color: colors[i % colors.length],
        value: value,
        title: isLarge && percent > 5 ? '${percent.toStringAsFixed(0)}%' : '',
        radius: isLarge ? 25 : 20, 
        titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
        borderSide: const BorderSide(color: Colors.white, width: 2), 
      );
    });
  }

  Widget _buildAssetTile(BuildContext context, MapEntry<String, int> item, int total, NumberFormat fmt) {
    final colorScheme = Theme.of(context).colorScheme;
    final percent = total > 0 ? (item.value / total * 100) : 0.0;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.account_balance_wallet, color: Colors.indigo, size: 20),
        ),
        title: Text(item.key, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('¥${fmt.format(item.value)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text('${percent.toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}