import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database.dart';
import 'add_pet_page.dart';

class PetRoomPage extends StatefulWidget {
  final MyDatabase db;
  const PetRoomPage({super.key, required this.db});

  @override
  State<PetRoomPage> createState() => _PetRoomPageState();
}

class _PetRoomPageState extends State<PetRoomPage> {
  List<AssetPet> _pets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPets();
  }

  Future<void> _loadPets() async {
    final pets = await widget.db.getAllAssetPets();
    setState(() {
      _pets = pets;
      _isLoading = false;
    });
  }

  Future<void> _deletePet(int id) async {
    await widget.db.deleteAssetPet(id);
    _loadPets();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? colorScheme.surface : Colors.grey.shade50,
      appBar: AppBar(title: const Text('資産ペット部屋 👾'), backgroundColor: Colors.transparent),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.pets, size: 80, color: isDark ? colorScheme.outline : Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        'まだペットがいません\n新しい資産を迎入れましょう！',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: isDark ? colorScheme.onSurfaceVariant : Colors.grey),
                      )
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: _pets.length,
                  itemBuilder: (context, index) {
                    final pet = _pets[index];
                    return _AnimatedPetCard(
                      pet: pet,
                      onDelete: () => _deletePet(pet.id),
                      isDark: isDark,
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.of(context).push(MaterialPageRoute(builder: (context) => AddPetPage(db: widget.db)));
          if (result == true) _loadPets();
        },
        label: const Text('資産を買う'),
        icon: const Icon(Icons.add_shopping_cart),
      ),
    );
  }
}

class _AnimatedPetCard extends StatefulWidget {
  final AssetPet pet;
  final VoidCallback onDelete;
  final bool isDark;

  const _AnimatedPetCard({required this.pet, required this.onDelete, required this.isDark});

  @override
  State<_AnimatedPetCard> createState() => _AnimatedPetCardState();
}

class _AnimatedPetCardState extends State<_AnimatedPetCard> with TickerProviderStateMixin {
  late AnimationController _moveController;
  late Animation<double> _moveAnimation;
  late AnimationController _scaleController; 
  
  String? _chatMessage;
  Timer? _chatTimer;
  
  // エフェクト用
  final List<_Particle> _particles = [];

  @override
  void initState() {
    super.initState();
    // ふわふわアニメーション
    _moveController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    final health = widget.pet.healthRatio;
    final double moveRange = health > 0.5 ? 8.0 : (health > 0.2 ? 4.0 : 1.0);
    _moveAnimation = Tween<double>(begin: 0, end: moveRange).animate(
      CurvedAnimation(parent: _moveController, curve: Curves.easeInOut),
    );

    // タップ時のスケールアニメーション
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      lowerBound: 0.8,
      upperBound: 1.0,
    )..value = 1.0;
  }

  @override
  void dispose() {
    _moveController.dispose();
    _scaleController.dispose();
    _chatTimer?.cancel();
    super.dispose();
  }

  // ★なでなでアクション
  void _onPetTap() {
    HapticFeedback.heavyImpact(); // 強めの振動
    _scaleController.forward(from: 0.8); // 縮んで戻る（プルン！）

    setState(() {
      // 複数のハートを飛び散らせる
      for (int i = 0; i < 5; i++) {
        _particles.add(_Particle());
      }
      
      // メッセージ更新
      _chatMessage = _getRandomMessage(widget.pet.healthRatio);
    });

    // メッセージ消去タイマー
    _chatTimer?.cancel();
    _chatTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _chatMessage = null;
        });
      }
    });

    // パーティクルアニメーション開始
    _startParticleAnimation();
  }

  void _startParticleAnimation() {
    Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_particles.isEmpty) {
        timer.cancel();
        return;
      }
      setState(() {
        _particles.removeWhere((p) => p.opacity <= 0);
        for (var p in _particles) {
          p.update();
        }
      });
    });
  }

  String _getRandomMessage(double health) {
    final List<String> high = ['えへへ♪', '大好き！', '調子いいよ！', '大事にしてね！', '資産価値MAX！', 'わーい！'];
    final List<String> mid = ['お仕事がんばる', '掃除してほしいな', 'まだまだ現役！', 'こんにちは！', 'なでなでして'];
    final List<String> low = ['腰が痛い...', 'そろそろ引退かな', '減価償却つらい...', '優しくして...', 'Zzz...'];

    if (health > 0.7) return high[Random().nextInt(high.length)];
    if (health > 0.2) return mid[Random().nextInt(mid.length)];
    return low[Random().nextInt(low.length)];
  }

  PetStyle _getPetStyle(int type, double health) {
    final bool isWeak = health < 0.2; 
    Color baseColor;
    IconData icon;
    String typeName;

    switch (type) {
      case 0: baseColor = Colors.blue; icon = Icons.laptop_mac; typeName = "Gadget"; break;
      case 1: baseColor = Colors.red; icon = Icons.directions_car_filled; typeName = "Vehicle"; break;
      case 2: baseColor = Colors.orange; icon = Icons.home_work; typeName = "Building"; break;
      default: baseColor = Colors.green; icon = Icons.pets; typeName = "Asset"; break;
    }

    if (isWeak) {
      return PetStyle(
        icon: icon,
        typeName: typeName,
        primaryColor: Colors.grey,
        gradient: LinearGradient(colors: [Colors.grey.shade400, Colors.blueGrey.shade200]),
        shadowColor: Colors.black.withValues(alpha: widget.isDark ? 0.3 : 0.1),
      );
    }
    return PetStyle(
      icon: icon,
      typeName: typeName,
      primaryColor: baseColor,
      gradient: LinearGradient(colors: [baseColor, baseColor.withValues(alpha: 0.6)]),
      shadowColor: baseColor.withValues(alpha: widget.isDark ? 0.4 : 0.2),
    );
  }

  String _getComment(double health) {
    if (health >= 0.9) return "ピカピカの新品！✨";
    if (health >= 0.7) return "調子はバッチリ！💪";
    if (health >= 0.5) return "まだまだ現役だよ！🏃";
    if (health >= 0.3) return "少し古くなってきた？🤔";
    if (health >= 0.1) return "そろそろ引退かな…👴";
    return "長い間ありがとう 🙏";
  }

  @override
  Widget build(BuildContext context) {
    final health = widget.pet.healthRatio;
    final style = _getPetStyle(widget.pet.characterType, health);
    final fmt = NumberFormat("#,###");
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = widget.isDark ? Colors.grey.shade300 : Colors.grey.shade700;
    final subTextColor = widget.isDark ? Colors.grey.shade500 : Colors.grey.shade500;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: widget.isDark ? colorScheme.surfaceContainerHigh : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: style.shadowColor, blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              right: -20, top: -20,
              child: Icon(style.icon, size: 150, color: style.primaryColor.withValues(alpha: 0.05)),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: style.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(children: [
                          Icon(style.icon, size: 14, color: style.primaryColor),
                          const SizedBox(width: 4),
                          Text(style.typeName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: style.primaryColor))
                        ]),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: subTextColor),
                        onPressed: widget.onDelete,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  
                  // メインエリア
                  Row(
                    children: [
                      // タップ可能エリア
                      GestureDetector(
                        onTapDown: (_) => _onPetTap(),
                        child: SizedBox(
                          width: 100, // 少し広めに
                          height: 100,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              // 吹き出し
                              if (_chatMessage != null)
                                Positioned(
                                  top: -40,
                                  left: -20,
                                  right: -20,
                                  child: _buildChatBubble(_chatMessage!, style.primaryColor),
                                ),

                              // パーティクル（ハート）描画
                              ..._particles.map((p) => Positioned(
                                left: 40 + p.x, 
                                top: 40 + p.y,
                                child: Opacity(
                                  opacity: p.opacity,
                                  child: Icon(Icons.favorite, size: p.size, color: Colors.pinkAccent.withOpacity(p.opacity)),
                                ),
                              )),

                              // 本体アニメーション
                              AnimatedBuilder(
                                animation: Listenable.merge([_moveAnimation, _scaleController]),
                                builder: (context, child) {
                                  return Transform.translate(
                                    offset: Offset(0, _moveAnimation.value),
                                    child: Transform.scale(
                                      scale: _scaleController.value, // タップで縮む
                                      child: child,
                                    ),
                                  );
                                },
                                child: Container(
                                  width: 80, height: 80,
                                  decoration: BoxDecoration(
                                    gradient: style.gradient,
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: style.primaryColor.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 5))],
                                  ),
                                  child: Icon(style.icon, size: 40, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.pet.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: widget.isDark ? colorScheme.onSurface : Colors.black)),
                            const SizedBox(height: 4),
                            Text(_getComment(health), style: TextStyle(fontSize: 14, color: textColor, fontStyle: FontStyle.italic)),
                            const SizedBox(height: 8),
                            Text("購入日: ${DateFormat('yyyy/MM/dd').format(widget.pet.purchaseDate)}", style: TextStyle(fontSize: 11, color: subTextColor)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // HPバー
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("現在の価値 (HP)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: subTextColor)),
                          Text("${fmt.format(widget.pet.currentValue)}円", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: style.primaryColor)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: health,
                        minHeight: 10,
                        backgroundColor: widget.isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                        color: style.primaryColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("購入額: ${fmt.format(widget.pet.price)}円", style: TextStyle(fontSize: 11, color: subTextColor)),
                          Text("寿命まであと約${(widget.pet.lifeYears * health).toStringAsFixed(1)}年", style: TextStyle(fontSize: 11, color: subTextColor)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble(String message, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(2, 2)),
        ],
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _Particle {
  double x = 0;
  double y = 0;
  double opacity = 1.0;
  double size = 10.0;
  double speedX = 0;
  double speedY = 0;

  _Particle() {
    final random = Random();
    x = 0;
    y = 0;
    speedX = (random.nextDouble() - 0.5) * 8; 
    speedY = -random.nextDouble() * 5 - 2; 
    size = random.nextDouble() * 15 + 10;
  }

  void update() {
    x += speedX;
    y += speedY;
    opacity -= 0.05; 
    if (opacity < 0) opacity = 0;
  }
}

class PetStyle {
  final IconData icon;
  final String typeName;
  final Color primaryColor;
  final Gradient gradient;
  final Color shadowColor;
  PetStyle({required this.icon, required this.typeName, required this.primaryColor, required this.gradient, required this.shadowColor});
}