import 'package:flutter/material.dart';
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

  // 見た目の設定（色、アイコン、背景グラデーション）
  PetStyle _getPetStyle(int type, double health) {
    final bool isWeak = health < 0.2; // 瀕死状態

    // ベースカラー定義
    Color baseColor;
    IconData icon;
    String typeName;

    switch (type) {
      case 0: // PC
        baseColor = Colors.blue;
        icon = Icons.laptop_mac;
        typeName = "Gadget";
        break;
      case 1: // 車
        baseColor = Colors.red;
        icon = Icons.directions_car_filled;
        typeName = "Vehicle";
        break;
      case 2: // 家
        baseColor = Colors.orange;
        icon = Icons.home_work;
        typeName = "Real Estate";
        break;
      default: // その他
        baseColor = Colors.green;
        icon = Icons.pets;
        typeName = "Asset";
        break;
    }

    if (isWeak) {
      return PetStyle(
        icon: icon,
        typeName: typeName,
        primaryColor: Colors.grey,
        gradient: LinearGradient(
          colors: [Colors.grey.shade400, Colors.blueGrey.shade200],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shadowColor: Colors.grey.withValues(alpha: 0.4),
      );
    }

    return PetStyle(
      icon: icon,
      typeName: typeName,
      primaryColor: baseColor,
      gradient: LinearGradient(
        colors: [baseColor, baseColor.withValues(alpha: 0.6)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      shadowColor: baseColor.withValues(alpha: 0.4),
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
    return Scaffold(
      backgroundColor: Colors.grey.shade100, // 背景を少しグレーに
      appBar: AppBar(
        title: const Text('資産ペット部屋 👾', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.pets, size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text('まだペットがいません\n新しい資産を迎入れましょう！', 
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80), // FAB分の余白
                  itemCount: _pets.length,
                  itemBuilder: (context, index) {
                    final pet = _pets[index];
                    final health = pet.healthRatio;
                    final style = _getPetStyle(pet.characterType, health);
                    final fmt = NumberFormat("#,###");

                    return _buildPetCard(context, pet, style, health, fmt);
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => AddPetPage(db: widget.db)),
          );
          if (result == true) {
            _loadPets();
          }
        },
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        label: const Text('資産を買う', style: TextStyle(fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add_shopping_cart),
      ),
    );
  }

  Widget _buildPetCard(BuildContext context, AssetPet pet, PetStyle style, double health, NumberFormat fmt) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: style.shadowColor,
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // 背景装飾（大きなアイコンを薄く表示）
            Positioned(
              right: -20,
              top: -20,
              child: Icon(
                style.icon,
                size: 150,
                color: style.primaryColor.withValues(alpha: 0.05),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  // ヘッダー部分
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: style.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(style.icon, size: 14, color: style.primaryColor),
                            const SizedBox(width: 4),
                            Text(
                              style.typeName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: style.primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_horiz, color: Colors.grey),
                        onPressed: () => _showDeleteDialog(pet),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 10),

                  // メインビジュアル
                  Row(
                    children: [
                      // アイコン（グラデーション背景）
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: style.gradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: style.primaryColor.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Icon(style.icon, size: 40, color: Colors.white),
                      ),
                      const SizedBox(width: 20),
                      
                      // 情報
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pet.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _getComment(health),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "誕生日: ${DateFormat('yyyy/MM/dd').format(pet.purchaseDate)}",
                              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // HPバー (価値)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("現在の価値 (HP)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                          Text(
                            "${fmt.format(pet.currentValue)}円",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: style.primaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Stack(
                        children: [
                          Container(
                            height: 12,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: health > 0 ? health : 0,
                            child: Container(
                              height: 12,
                              decoration: BoxDecoration(
                                gradient: style.gradient,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("購入額: ${fmt.format(pet.price)}円", style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          Text("寿命まであと約${(pet.lifeYears * health).toStringAsFixed(1)}年", style: const TextStyle(fontSize: 11, color: Colors.grey)),
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

  void _showDeleteDialog(AssetPet pet) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('お別れしますか？'),
        content: Text('${pet.name} を削除します。\n（資産データから消えます）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deletePet(pet.id);
            },
            child: const Text('さようなら', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class PetStyle {
  final IconData icon;
  final String typeName;
  final Color primaryColor;
  final Gradient gradient;
  final Color shadowColor;

  PetStyle({
    required this.icon,
    required this.typeName,
    required this.primaryColor,
    required this.gradient,
    required this.shadowColor,
  });
}