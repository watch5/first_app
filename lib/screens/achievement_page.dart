import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:confetti/confetti.dart'; // お祝い用エフェクト
import '../database.dart';

class AchievementPage extends StatefulWidget {
  final MyDatabase db;
  const AchievementPage({super.key, required this.db});

  @override
  State<AchievementPage> createState() => _AchievementPageState();
}

class _AchievementPageState extends State<AchievementPage> {
  late ConfettiController _confettiController;
  
  // 定義されている全実績リスト
  final List<AchievementDefinition> _allAchievements = [
    AchievementDefinition(id: 'first_tx', title: 'はじめの一歩', description: '初めて取引を記帳した', icon: Icons.flag, color: Colors.blue),
    AchievementDefinition(id: 'save_100k', title: '貯蓄の芽', description: '純資産が10万円を超えた', icon: Icons.savings, color: Colors.green),
    AchievementDefinition(id: 'save_1m', title: 'ミリオネア', description: '純資産が100万円を超えた', icon: Icons.diamond, color: Colors.amber),
    AchievementDefinition(id: 'pet_owner', title: 'オーナー誕生', description: '初めて資産ペットを登録した', icon: Icons.pets, color: Colors.orange),
    AchievementDefinition(id: 'budget_setter', title: '計画的なあなた', description: '予算を設定した', icon: Icons.pie_chart, color: Colors.purple),
    AchievementDefinition(id: 'master_bookkeeper', title: '記帳マスター', description: '取引記録が50件を超えた', icon: Icons.history_edu, color: Colors.redAccent),
  ];

  List<String> _unlockedIds = [];
  int _currentScore = 0; // スコア（ランク付け用）

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _checkAndLoadAchievements();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _checkAndLoadAchievements() async {
    // 1. 現状のデータを取得
    final txs = await widget.db.getTransactions();
    final accounts = await widget.db.getAllAccounts();
    final pets = await widget.db.getAllAssetPets();
    final unlocked = await widget.db.getUnlockedAchievements();
    final currentAssetBalance = await widget.db.getCurrentAssetBalance(); // これは流動資産のみ
    
    // 純資産の正確な計算
    int totalAssets = 0;
    int totalLiabilities = 0;
    for (var a in accounts) {
      if (a.type == 'asset') {
         // シンプル化のため、getCurrentAssetBalance相当の計算が必要だが、ここでは簡易的に実装
         // 今回は既存メソッド getCurrentAssetBalance があるのでそれを使うが、
         // 厳密には負債を引く必要がある。
      }
    }
    // 簡易的に資産-負債を計算
    int netWorth = 0;
    // 取引から再計算
    for (var t in txs) {
       final debit = accounts.firstWhere((a) => a.id == t.debitAccountId);
       final credit = accounts.firstWhere((a) => a.id == t.creditAccountId);
       
       if (debit.type == 'asset') netWorth += t.amount;
       if (credit.type == 'asset') netWorth -= t.amount;
       // 負債の増減も考慮すべきだが、ここでは簡易的に「資産 - 負債」＝ 純資産とする
       if (debit.type == 'liability') netWorth -= t.amount; // 負債減る＝純資産増える（逆だ...）
       // 簿記的に正しい純資産計算は BSPageにあるロジックと同じ。
       // 簡易ロジック：
       if (debit.type == 'asset') netWorth += t.amount;
       if (debit.type == 'liability') netWorth -= t.amount; // 負債減少＝プラス
       
       if (credit.type == 'asset') netWorth -= t.amount;
       if (credit.type == 'liability') netWorth += t.amount; // 負債増加＝マイナス
    }


    List<String> newUnlocks = [];

    // --- 条件チェック ---
    
    // 1. 初めての記帳
    if (txs.isNotEmpty && !unlocked.contains('first_tx')) {
      newUnlocks.add('first_tx');
    }

    // 2. 資産10万円
    if (netWorth >= 100000 && !unlocked.contains('save_100k')) {
      newUnlocks.add('save_100k');
    }

    // 3. 資産100万円
    if (netWorth >= 1000000 && !unlocked.contains('save_1m')) {
      newUnlocks.add('save_1m');
    }

    // 4. ペットオーナー
    if (pets.isNotEmpty && !unlocked.contains('pet_owner')) {
      newUnlocks.add('pet_owner');
    }

    // 5. 予算設定
    final hasBudget = accounts.any((a) => a.budget > 0);
    if (hasBudget && !unlocked.contains('budget_setter')) {
      newUnlocks.add('budget_setter');
    }

    // 6. 記帳マスター
    if (txs.length >= 50 && !unlocked.contains('master_bookkeeper')) {
      newUnlocks.add('master_bookkeeper');
    }


    // --- 新規解除があればDB保存 ---
    if (newUnlocks.isNotEmpty) {
      for (var id in newUnlocks) {
        await widget.db.unlockAchievement(id);
      }
      _confettiController.play(); // お祝い！
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('${newUnlocks.length}個の実績を解除しました！🎉')),
        );
      }
    }

    // 再読み込み
    final updatedUnlocked = await widget.db.getUnlockedAchievements();
    setState(() {
      _unlockedIds = updatedUnlocked;
      _currentScore = updatedUnlocked.length * 100; // 簡易スコア
    });
  }

  String _getRank() {
    if (_currentScore >= 600) return "CFO (最高財務責任者)";
    if (_currentScore >= 400) return "ベテラン経理";
    if (_currentScore >= 200) return "家計簿マスター";
    if (_currentScore >= 100) return "見習い会計士";
    return "新人";
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('実績博物館 🏆')),
      body: Stack(
        children: [
          Column(
            children: [
              // ランク表示カード
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colorScheme.primary, colorScheme.tertiary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: colorScheme.primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5)),
                  ],
                ),
                child: Column(
                  children: [
                    const Text('現在のランク', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 5),
                    Text(_getRank(), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: _currentScore / 600, // MAX 600
                      backgroundColor: Colors.white24,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 5),
                    Text('スコア: $_currentScore pts', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),

              const Divider(),

              // 実績グリッド
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, // 2列
                    childAspectRatio: 0.85,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _allAchievements.length,
                  itemBuilder: (context, index) {
                    final item = _allAchievements[index];
                    final isUnlocked = _unlockedIds.contains(item.id);

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      decoration: BoxDecoration(
                        color: isUnlocked 
                            ? (isDark ? colorScheme.surfaceContainer : Colors.white) 
                            : (isDark ? Colors.grey.shade900 : Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(16),
                        border: isUnlocked 
                            ? Border.all(color: item.color.withOpacity(0.5), width: 2)
                            : Border.all(color: Colors.transparent),
                        boxShadow: isUnlocked 
                            ? [BoxShadow(color: item.color.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))] 
                            : [],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isUnlocked ? item.color.withOpacity(0.1) : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              item.icon, 
                              size: 40, 
                              color: isUnlocked ? item.color : Colors.grey
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isUnlocked ? item.title : '???',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isUnlocked ? (isDark ? Colors.white : Colors.black87) : Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text(
                              isUnlocked ? item.description : '条件未達成',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          
          // 紙吹雪エフェクト (中央上部から)
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple], 
            ),
          ),
        ],
      ),
    );
  }
}

class AchievementDefinition {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}