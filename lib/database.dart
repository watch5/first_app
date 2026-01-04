import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

part 'database.g.dart';

// --- 1. 勘定科目テーブル ---
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); // 科目名
  TextColumn get type => text()(); // asset, liability, expense, income
  // ★追加: 月予算 (null許容)
  IntColumn get monthlyBudget => integer().nullable()();
}

// --- 2. 取引テーブル ---
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get debitAccountId => integer().references(Accounts, #id)();
  IntColumn get creditAccountId => integer().references(Accounts, #id)();
  IntColumn get amount => integer()();
  DateTimeColumn get date => dateTime()();
}

// --- 3. データベース本体 ---
@DriftDatabase(tables: [Accounts, Transactions])
class MyDatabase extends _$MyDatabase {
  MyDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  // ★マイグレーション処理 (バージョンアップ時のルール)
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) => m.createAll(),
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        // バージョン1→2の時、monthly_budget列を追加する
        await m.addColumn(accounts, accounts.monthlyBudget);
      }
    },
  );

  // 全ての取引を取得
  Future<List<Transaction>> getTransactions() => select(transactions).get();

  // 全ての科目を取得
  Future<List<Account>> getAllAccounts() => select(accounts).get();

  // 取引を追加
  Future<int> addTransaction(int debitId, int creditId, int amount, DateTime date) {
    return into(transactions).insert(TransactionsCompanion(
      debitAccountId: Value(debitId),
      creditAccountId: Value(creditId),
      amount: Value(amount),
      date: Value(date),
    ));
  }

// ★変更: 科目追加時に予算も登録できるようにする
  Future<int> addAccount(String name, String type, int? budget) {
    return into(accounts).insert(AccountsCompanion(
      name: Value(name),
      type: Value(type),
      monthlyBudget: Value(budget),
    ));
  }

  // ★追加: 科目の予算を更新する機能
  Future<void> updateAccountBudget(int id, int budget) {
    return (update(accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(monthlyBudget: Value(budget)),
    );
  }
  
  // 取引を削除
  Future<int> deleteTransaction(int id) {
    return (delete(transactions)..where((t) => t.id.equals(id))).go();
  }

  // 初期データ投入
  Future<void> seedDefaultAccounts() async {
    final count = await select(accounts).get().then((l) => l.length);
    if (count == 0) {
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
          // 負債 (Liability)
          AccountsCompanion.insert(name: 'クレカ', type: 'liability'),
        ]);
      });
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}