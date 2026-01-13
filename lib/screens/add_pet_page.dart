import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../database.dart';

class AddPetPage extends StatefulWidget {
  final MyDatabase db;
  const AddPetPage({super.key, required this.db});

  @override
  State<AddPetPage> createState() => _AddPetPageState();
}

class _AddPetPageState extends State<AddPetPage> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _lifeYearsController = TextEditingController(text: '4'); // デフォルト4年

  DateTime _purchaseDate = DateTime.now();
  int _selectedCharacterType = 0; // 0:PC, 1:車, 2:家, 3:その他

  // キャラクターの選択肢
  final List<(int, IconData, String)> _characters = [
    (0, Icons.computer, 'PC・ガジェット'),
    (1, Icons.directions_car, '車・バイク'),
    (2, Icons.home, '家・建物'),
    (3, Icons.pets, 'その他'),
  ];

  // よくある耐用年数のプリセット
  final List<(String, int)> _lifePresets = [
    ('PC', 4),
    ('スマホ', 2),
    ('車', 6),
    ('家具', 8),
    ('建物', 20),
  ];

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(1980),
      lastDate: DateTime.now(), // 未来の資産は買えない
      locale: const Locale('ja'),
    );
    if (picked != null) {
      setState(() => _purchaseDate = picked);
    }
  }

  void _save() async {
    final name = _nameController.text;
    final price = int.tryParse(_priceController.text) ?? 0;
    final lifeYears = int.tryParse(_lifeYearsController.text) ?? 0;

    if (name.isEmpty || price <= 0 || lifeYears <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正しい情報を入力してください')));
      return;
    }

    await widget.db.addAssetPet(name, price, _purchaseDate, lifeYears, _selectedCharacterType);
    
    if (mounted) Navigator.pop(context, true); // trueを返してリロードを促す
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('新しい資産を迎える')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 名前
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '資産の名前（ペット名）',
                hintText: '例: MacBook Pro',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit),
              ),
            ),
            const SizedBox(height: 16),

            // 金額
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '購入価格 (円)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.currency_yen),
              ),
            ),
            const SizedBox(height: 16),

            // 購入日
            ListTile(
              title: Text('購入日 (誕生日): ${DateFormat('yyyy/MM/dd').format(_purchaseDate)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectDate,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade400)),
            ),
            const SizedBox(height: 24),

            const Text('耐用年数 (寿命)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            // 耐用年数プリセット
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _lifePresets.map((preset) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text('${preset.$1} (${preset.$2}年)'),
                      selected: _lifeYearsController.text == preset.$2.toString(),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _lifeYearsController.text = preset.$2.toString());
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _lifeYearsController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '年数',
                border: OutlineInputBorder(),
                suffixText: '年',
              ),
            ),
            const SizedBox(height: 24),

            const Text('キャラクター (見た目)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _characters.map((char) {
                final isSelected = _selectedCharacterType == char.$1;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCharacterType = char.$1),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected ? colorScheme.primaryContainer : Colors.grey.shade100,
                          shape: BoxShape.circle,
                          border: isSelected ? Border.all(color: colorScheme.primary, width: 2) : null,
                        ),
                        child: Icon(char.$2, size: 30, color: isSelected ? colorScheme.primary : Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(char.$3, style: TextStyle(fontSize: 10, color: isSelected ? colorScheme.primary : Colors.grey)),
                    ],
                  ),
                );
              }).toList(),
            ),
            
            const SizedBox(height: 40),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: const Text('この子を迎え入れる', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}