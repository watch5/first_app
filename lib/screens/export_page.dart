import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../database.dart';

class ExportPage extends StatefulWidget {
  final MyDatabase db;
  const ExportPage({super.key, required this.db});

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  bool _isExporting = false;

  Future<void> _exportToCsv() async {
    setState(() => _isExporting = true);

    try {
      final transactions = await widget.db.getTransactions();
      final accounts = await widget.db.getAllAccounts();
      final accountMap = {for (var a in accounts) a.id: a.name};

      // CSVデータの作成 (ヘッダー + データ)
      List<List<dynamic>> rows = [
        ["ID", "日付", "借方(用途)", "貸方(元)", "金額", "メモ", "自動入力"], // ヘッダー
      ];

      for (var t in transactions) {
        rows.add([
          t.id,
          DateFormat('yyyy/MM/dd').format(t.date),
          accountMap[t.debitAccountId] ?? '不明',
          accountMap[t.creditAccountId] ?? '不明',
          t.amount,
          t.note ?? '',
          t.isAuto == 1 ? 'Yes' : 'No',
        ]);
      }

      // CSV文字列に変換
      String csvData = const ListToCsvConverter().convert(rows);

      // 一時ファイルに保存
      final directory = await getTemporaryDirectory();
      final path = "${directory.path}/dualy_data_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv";
      final file = File(path);
      await file.writeAsString(csvData);

      // シェア機能でファイルを送る (iOS/Android共通)
      await Share.shareXFiles([XFile(path)], text: 'Dualyの取引データです');

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラーが発生しました: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('データ出力 (CSV)')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.file_download, size: 100, color: Colors.teal),
              const SizedBox(height: 24),
              const Text(
                '取引データをCSV形式で出力します。\nExcelやスプレッドシートで管理したり、\nバックアップとして保存できます。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: _isExporting ? null : _exportToCsv,
                  icon: _isExporting 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                      : const Icon(Icons.share),
                  label: Text(_isExporting ? '作成中...' : 'CSVファイルを書き出して共有'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}