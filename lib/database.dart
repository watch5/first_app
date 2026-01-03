import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

// 魔法の呪文（このファイルの名前 'database.dart' に対応したコードが生成される）
part 'database.g.dart';

// --- 1. テーブルの設計図 ---
class Transactions extends Table {
  // id: 背番号（自動で増える）
  IntColumn get id => integer().autoIncrement()();
  // title: 品目
  TextColumn get title => text()();
  // amount: 金額
  IntColumn get amount => integer()();
  // date: 日付
  DateTimeColumn get date => dateTime()();
}

// --- 2. データベース本体 ---
@DriftDatabase(tables: [Transactions])
class MyDatabase extends _$MyDatabase {
  // コンストラクタ（保存場所を指定して開く）
  MyDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1; // バージョン番号（変更したら上げる）

  // --- 便利な命令（メソッド）たち ---

  // 全データを取得する
  Future<List<Transaction>> getAllTransactions() => select(transactions).get();

  // 新しいデータを追加する
  Future<int> addTransaction(String title, int amount, DateTime date) {
    return into(transactions).insert(TransactionsCompanion(
      title: Value(title),
      amount: Value(amount),
      date: Value(date),
    ));
  }
  
  // データを削除する（おまけ）
  Future<int> deleteTransaction(int id) {
    return (delete(transactions)..where((t) => t.id.equals(id))).go();
  }
}

// --- 3. スマホ内の保存場所を見つける処理 ---
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // アプリ専用のドキュメントフォルダを取得
    final dbFolder = await getApplicationDocumentsDirectory();
    // その中に 'db.sqlite' というファイルを作る
    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}