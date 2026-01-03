import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

part 'database.g.dart';

// --- 1. 勘定科目テーブル（New!） ---
// 例：現金, 銀行, 食費, 給料 など
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); // 科目名
  TextColumn get type => text()(); // asset(資産), liability(負債), expense(費用), income(収益)
}

// --- 2. 取引テーブル（リニューアル！） ---
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  // 文字のタイトルではなく、「どの科目か（ID）」を記録します
  IntColumn get debitAccountId => integer().references(Accounts, #id)();  // 借方（増えたもの：食費など）
  IntColumn get creditAccountId => integer().references(Accounts, #id)(); // 貸方（減ったもの：現金など）
  IntColumn get amount => integer()();
  DateTimeColumn get date => dateTime()();
}

// --- 3. データベース本体 ---
@DriftDatabase(tables: [Accounts, Transactions])
class MyDatabase extends _$MyDatabase {
  MyDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // --- 便利なメソッド集 ---

  // 全ての取引を、科目名付きで取得する（結合クエリ）
  Future<List<TransactionWithAccount>> getAllTransactions() async {
    // SQLの JOIN（結合）と同じことをDriftでやります
    final query = select(transactions).join([
      leftOuterJoin(accounts, accounts.id.equalsExp(transactions.debitAccountId), useColumns: false), // 借方の名前用
    ]);
    
    // ※今回は簡易化のため、とりあえず標準のselectで取得し、画面側で名前を解決する方式にします。
    // 本格的なJOINは少しコードが複雑になるため、まずはデータ構造の変更を優先します。
    return []; // このメソッドは後で実装します
  }
  
  // シンプルな全取引取得
  Future<List<Transaction>> getTransactions() => select(transactions).get();

  // 全ての科目を取得
  Future<List<Account>> getAllAccounts() => select(accounts).get();

  // 新しい取引を追加
  Future<int> addTransaction(int debitId, int creditId, int amount, DateTime date) {
    return into(transactions).insert(TransactionsCompanion(
      debitAccountId: Value(debitId),
      creditAccountId: Value(creditId),
      amount: Value(amount),
      date: Value(date),
    ));
  }

  // 初期データ（マスタ）の投入
  Future<void> seedDefaultAccounts() async {
    final count = await select(accounts).get().then((l) => l.length);
    if (count == 0) {
      // データが空っぽなら、デフォルトの科目を作る
      await batch((batch) {
        batch.insertAll(accounts, [
          // 資産 (Assets)
          AccountsCompanion.insert(name: '現金', type: 'asset'),
          AccountsCompanion.insert(name: '銀行口座', type: 'asset'),
          // 費用 (Expenses)
          AccountsCompanion.insert(name: '食費', type: 'expense'),
          AccountsCompanion.insert(name: '交通費', type: 'expense'),
          AccountsCompanion.insert(name: '日用品', type: 'expense'),
          AccountsCompanion.insert(name: 'エンタメ', type: 'expense'),
          // 収益 (Income)
          AccountsCompanion.insert(name: '給与', type: 'income'),
        ]);
      });
    }
  }
  
  // 削除
  Future<int> deleteTransaction(int id) {
    return (delete(transactions)..where((t) => t.id.equals(id))).go();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

// 画面表示用の便利なクラス（拡張）
class TransactionWithAccount {
  final Transaction transaction;
  final Account debit;  // 借方科目（食費など）
  final Account credit; // 貸方科目（現金など）
  TransactionWithAccount(this.transaction, this.debit, this.credit);
}