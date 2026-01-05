import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

// --- 1. 勘定科目テーブル ---
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // 'asset', 'liability', 'income', 'expense'
  IntColumn get monthlyBudget => integer().nullable()();
}

// --- 2. 取引明細テーブル ---
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get debitAccountId => integer()();
  IntColumn get creditAccountId => integer()();
  IntColumn get amount => integer()();
  DateTimeColumn get date => dateTime()();
}

// --- 3. テンプレートテーブル ---
class Templates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); 
  IntColumn get debitAccountId => integer()();
  IntColumn get creditAccountId => integer()();
  IntColumn get amount => integer()();
}

// --- データベース本体 ---
@DriftDatabase(tables: [Accounts, Transactions, Templates]) 
class MyDatabase extends _$MyDatabase {
  // ★ここでエラーが出ていたのは、_openConnection がこのクラスの中にあったからです。
  // 下の方にある _openConnection() を呼び出します。
  MyDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) => m.createAll(),
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.addColumn(accounts, accounts.monthlyBudget);
      }
      if (from < 3) {
        await m.createTable(templates);
      }
    },
  );

  // --- クエリ ---

  // Accounts
  Future<List<Account>> getAllAccounts() => select(accounts).get();
  Future<int> addAccount(String name, String type, int? budget) {
    return into(accounts).insert(AccountsCompanion(
      name: Value(name),
      type: Value(type),
      monthlyBudget: Value(budget),
    ));
  }
  Future<void> updateAccountBudget(int id, int budget) {
    return (update(accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(monthlyBudget: Value(budget)),
    );
  }

  // Transactions
  Future<List<Transaction>> getTransactions() => select(transactions).get();
  Future<int> addTransaction(int debitId, int creditId, int amount, DateTime date) {
    return into(transactions).insert(TransactionsCompanion(
      debitAccountId: Value(debitId),
      creditAccountId: Value(creditId),
      amount: Value(amount),
      date: Value(date),
    ));
  }
  Future<void> deleteTransaction(int id) {
    return (delete(transactions)..where((t) => t.id.equals(id))).go();
  }

  // --- 取引データの更新 (編集用) ---
  Future<void> updateTransaction(int id, int debitId, int creditId, int amount, DateTime date) {
    return (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        debitAccountId: Value(debitId),
        creditAccountId: Value(creditId),
        amount: Value(amount),
        date: Value(date),
      ),
    );
  }

// 科目を削除する（関連する取引データも全て削除する）
  Future<void> deleteAccount(int id) {
    // transactionで囲むことで、万が一途中でエラーが出ても整合性を保ちます
    return transaction(() async {
      // 1. まず、その科目を使っている取引を全て削除する
      // (Driftの書き方: | は OR を意味します)
      await (delete(transactions)..where((t) => 
        t.debitAccountId.equals(id) | t.creditAccountId.equals(id)
      )).go();
      
      // 2. 次に、科目自体を削除する
      await (delete(accounts)..where((a) => a.id.equals(id))).go();
    });
  }

  // Templates
  Future<List<Template>> getAllTemplates() => select(templates).get();
  Future<int> addTemplate(String name, int debitId, int creditId, int amount) {
    return into(templates).insert(TemplatesCompanion(
      name: Value(name),
      debitAccountId: Value(debitId),
      creditAccountId: Value(creditId),
      amount: Value(amount),
    ));
  }
  Future<void> deleteTemplate(int id) {
    return (delete(templates)..where((t) => t.id.equals(id))).go();
  }

  // ★初期データ投入（リッチ版）
  Future<void> seedDefaultAccounts() async {
    final allAccounts = await getAllAccounts();
    if (allAccounts.isEmpty) {
      // --- 資産 (Assets) ---
      await addAccount('現金', 'asset', null);
      await addAccount('銀行口座', 'asset', null);
      await addAccount('PayPay', 'asset', null);
      await addAccount('Suica/PASMO', 'asset', null);

      // --- 負債 (Liabilities) ---
      await addAccount('クレジットカード', 'liability', null);
      
      // --- 収益 (Income) ---
      await addAccount('給料', 'income', null);
      await addAccount('ボーナス', 'income', null);
      await addAccount('臨時収入', 'income', null);

      // --- 費用 (Expenses) ---
      // 固定費
      await addAccount('家賃', 'expense', 70000);
      await addAccount('電気代', 'expense', 5000);
      await addAccount('ガス代', 'expense', 4000);
      await addAccount('水道代', 'expense', 3000);
      await addAccount('通信費', 'expense', 5000); // スマホ・ネット
      
      // 変動費
      await addAccount('食費', 'expense', 30000);
      await addAccount('外食', 'expense', 10000);
      await addAccount('日用品', 'expense', 5000);
      await addAccount('交通費', 'expense', 10000);
      await addAccount('衣服・美容', 'expense', 10000);
      await addAccount('交際費', 'expense', 10000);
      await addAccount('医療費', 'expense', 5000);
      await addAccount('趣味・娯楽', 'expense', 10000); // 推し活など
      await addAccount('その他', 'expense', 5000);
    }
  }
} // ★重要：クラスはここで閉じる！

// ★重要：この関数はクラスの「外」に置く必要があります！
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}