import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../database.dart';
import 'add_transaction_page.dart';

class ReceiptScanPage extends StatefulWidget {
  final MyDatabase db;
  const ReceiptScanPage({super.key, required this.db});

  @override
  State<ReceiptScanPage> createState() => _ReceiptScanPageState();
}

class _ReceiptScanPageState extends State<ReceiptScanPage> {
  final ImagePicker _picker = ImagePicker();
  bool _isScanning = false;
  String _status = 'レシートを撮影してください';

  Future<void> _scanReceipt(ImageSource source) async {
    setState(() {
      _isScanning = true;
      _status = 'カメラを起動中...';
    });

    try {
      // ★修正1: 画像サイズを600px、画質50%まで落としてメモリ不足を回避
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 600, 
        maxHeight: 600, 
        imageQuality: 50, 
        requestFullMetadata: false, 
      );
      
      if (image == null) {
        setState(() {
          _isScanning = false;
          _status = 'キャンセルされました';
        });
        return;
      }

      if (!mounted) return;
      setState(() => _status = '画像を解析しています...');

      // ★修正2: スマホの処理負荷を下げるため、0.5秒待機（クールダウン）
      await Future.delayed(const Duration(milliseconds: 500));

      final inputImage = InputImage.fromFilePath(image.path);
      
      // 日本語認識を使用
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.japanese);
      
      // 解析実行
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      await textRecognizer.close();

      // --- 解析ロジック ---
      int foundAmount = 0;
      DateTime foundDate = DateTime.now();
      String foundMerchant = "";

      List<String> lines = recognizedText.blocks.map((block) => block.text).toList();
      
      if (lines.isNotEmpty) {
        foundMerchant = lines.first.split('\n').first;
      }

      // 日付検出 (2023/01/01, 2023-01-01, 2023年1月1日)
      final dateRegex = RegExp(r'(\d{4})[年/.-](\d{1,2})[月/.-](\d{1,2})');
      for (String text in lines) {
        final match = dateRegex.firstMatch(text);
        if (match != null) {
          int y = int.parse(match.group(1)!);
          int m = int.parse(match.group(2)!);
          int d = int.parse(match.group(3)!);
          foundDate = DateTime(y, m, d);
          break;
        }
      }

      // 金額検出
      List<int> amounts = [];
      final amountRegex = RegExp(r'¥?\s*([\d,]+)'); 

      for (String text in lines) {
        if (text.contains('-') && text.length > 9) continue; 
        final matches = amountRegex.allMatches(text);
        for (var m in matches) {
          String numStr = m.group(1)!.replaceAll(',', '');
          int? val = int.tryParse(numStr);
          if (val != null && val > 0 && val < 10000000) {
            amounts.add(val);
          }
        }
      }
      
      if (amounts.isNotEmpty) {
        amounts.sort();
        foundAmount = amounts.last;
      }

      if (!mounted) return;
      
      setState(() {
        _isScanning = false;
        _status = '解析完了！';
      });

      _navigateToAddPage(foundAmount, foundDate, foundMerchant);

    } catch (e) {
      debugPrint('Scan Error: $e');
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _status = 'エラーが発生しました:\n$e';
      });
    }
  }

  Future<void> _navigateToAddPage(int amount, DateTime date, String note) async {
    final accounts = await widget.db.getAllAccounts();
    if (!mounted) return;

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddTransactionPage(
          accounts: accounts,
          db: widget.db,
          initialData: Transaction(
            id: 0,
            debitAccountId: -1,
            creditAccountId: -1,
            amount: amount,
            date: date,
            note: note,
          ),
        ),
      ),
    );

    if (result != null && !result.containsKey('id')) {
      await widget.db.addTransaction(
        result['debitId'], 
        result['creditId'], 
        result['amount'],
        result['date'],
        note: result['note'],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('記帳しました！')));
        Navigator.pop(context); 
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('レシート読み込み')),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isScanning)
                const CircularProgressIndicator()
              else
                const Icon(Icons.receipt_long, size: 100, color: Colors.blueGrey),
              
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(_status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 48),
              
              SizedBox(
                width: 250,
                height: 50,
                child: FilledButton.icon(
                  onPressed: _isScanning ? null : () => _scanReceipt(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('カメラで撮影'),
                ),
              ),
              const SizedBox(height: 16),
              
              SizedBox(
                width: 250,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _isScanning ? null : () => _scanReceipt(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('アルバムから選択'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}