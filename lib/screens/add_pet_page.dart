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
  final _lifeYearsController = TextEditingController(text: '4');

  DateTime _purchaseDate = DateTime.now();
  int _selectedCharacterType = 0;

  final List<(int, IconData, String, Color)> _characters = [
    (0, Icons.laptop_mac, 'ガジェット', Colors.blue),
    (1, Icons.directions_car_filled, '乗り物', Colors.red),
    (2, Icons.home_work, '建物', Colors.orange),
    (3, Icons.pets, 'その他', Colors.green),
  ];

  final List<(String, int)> _lifePresets = [
    ('PC/スマホ', 4), ('車', 6), ('家具', 8), ('建物', 22),
  ];

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(1980),
      lastDate: DateTime.now(),
      locale: const Locale('ja'),
    );
    if (picked != null) setState(() => _purchaseDate = picked);
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
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('新しい資産を迎える')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Text('どんな資産ですか？', style: TextStyle(color: colorScheme.secondary))),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _characters.map((char) {
                final isSelected = _selectedCharacterType == char.$1;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedCharacterType = char.$1);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected ? char.$4.withValues(alpha: 0.1) : Colors.grey.shade50,
                      shape: BoxShape.circle,
                      border: Border.all(color: isSelected ? char.$4 : Colors.grey.shade200, width: isSelected ? 3 : 1),
                      boxShadow: isSelected ? [BoxShadow(color: char.$4.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))] : [],
                    ),
                    child: Icon(char.$2, size: 32, color: isSelected ? char.$4 : Colors.grey),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),

            TextField(controller: _nameController, decoration: const InputDecoration(labelText: '資産の名前（ペット名）', hintText: '例: MacBook Pro', border: OutlineInputBorder(), prefixIcon: Icon(Icons.edit))),
            const SizedBox(height: 20),
            TextField(controller: _priceController, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: '購入価格 (円)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.currency_yen))),
            const SizedBox(height: 20),
            InkWell(
              onTap: _selectDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: '購入日 (誕生日)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.cake)),
                child: Text(DateFormat('yyyy/MM/dd').format(_purchaseDate), style: const TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 32),

            const Text('耐用年数（寿命）', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _lifePresets.map((preset) {
                final isSelected = _lifeYearsController.text == preset.$2.toString();
                return FilterChip(
                  label: Text('${preset.$1} (${preset.$2}年)'),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      HapticFeedback.selectionClick();
                      setState(() => _lifeYearsController.text = preset.$2.toString());
                    }
                  },
                  checkmarkColor: Colors.white,
                  selectedColor: colorScheme.primary,
                  labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(controller: _lifeYearsController, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: '年数を手動入力', border: OutlineInputBorder(), suffixText: '年')),
            
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: const Text('この子を迎え入れる', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}