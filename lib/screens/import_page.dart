import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database.dart';

class ImportPage extends StatefulWidget {
  final MyDatabase db;
  const ImportPage({super.key, required this.db});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  bool _isImporting = false;
  String _statusMessage = 'CSVファイルを選択してください';

  Future<void> _pickAndImportCsv() async {
    try {
      // ファイル選択
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null || result.files.single.path == null) {
        return; // キャンセル
      }

      setState(() {
        _isImporting = true;
        _statusMessage = 'データを解析中...';
      });

      final file = File(result.files.single.path!);
      final input = await file.readAsString();
      
      // CSVをリストに変換 (改行コード対応)
      final List<List<dynamic>> rows = const CsvToListConverter(eol: '\n').convert(input);

      if (rows.isEmpty || rows.length < 2) {
        throw Exception('データが見つかりません');
      }

      // 1行目はヘッダーなのでスキップ
      // フォーマット: [ID, 日付, 借方, 貸方, 金額, メモ, 自動入力]
      int successCount = 0;
      
      // 事前に全科目をロードしてキャッシュ
      List<Account> accounts = await widget.db.getAllAccounts();

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length < 7) continue; // 列不足はスキップ

        // データのパース
        final dateStr = row[1].toString();
        final debitName = row[2].toString();
        final creditName = row[3].toString();
        final amount = int.tryParse(row[4].toString()) ?? 0;
        final note = row[5].toString();
        final isAutoStr = row[6].toString();

        DateTime date;
        try {
          date = DateFormat('yyyy/MM/dd').parse(dateStr);
        } catch (e) {
          continue; // 日付エラーはスキップ
        }

        // 科目IDの特定（なければ作成）
        final debitId = await _getOrCreateAccountId(debitName, 'expense', accounts);
        // 科目リストを再取得（作成された可能性があるため）
        if (!accounts.any((a) => a.id == debitId)) accounts = await widget.db.getAllAccounts();
        
        final creditId = await _getOrCreateAccountId(creditName, 'asset', accounts);
        if (!accounts.any((a) => a.id == creditId)) accounts = await widget.db.getAllAccounts();

        // 取引の登録
        await widget.db.addTransaction(
          debitId,
          creditId,
          amount,
          date,
          note: note,
          isAuto: isAutoStr == 'Yes',
        );
        successCount++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$successCount 件のデータを取り込みました！')),
        );
        Navigator.pop(context); // 完了したら戻る
      }

    } catch (e) {
      setState(() => _statusMessage = 'エラー: $e');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  // 科目名からIDを取得、なければ作成してIDを返す
  Future<int> _getOrCreateAccountId(String name, String defaultType, List<Account> currentAccounts) async {
    // 既存チェック
    final existing = currentAccounts.firstWhere(
      (a) => a.name == name, 
      orElse: () => const Account(id: -1, name: '', type: '', costType: ''),
    );

    if (existing.id != -1) {
      return existing.id;
    }

    // 新規作成
    // ※タイプなどは推測できないため、デフォルト値を使用
    await widget.db.addAccount(name, defaultType, 0, 'variable');
    
    // 作成したIDを取得して返す
    final newAccounts = await widget.db.getAllAccounts();
    return newAccounts.firstWhere((a) => a.name == name).id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('データ取り込み (インポート)')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.file_upload, size: 100, color: Colors.orange),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 48),
              if (_isImporting)
                const CircularProgressIndicator()
              else
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _pickAndImportCsv,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('CSVファイルを選択'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                '※ 重複データも新規として追加されます。\n※ 知らない科目名は自動で作成されます。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}