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
  // バージョン2で追加
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

// --- ★3. テンプレートテーブル (New!) ---
class Templates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); // テンプレート名
  IntColumn get debitAccountId => integer()();
  IntColumn get creditAccountId => integer()();
  IntColumn get amount => integer()();
}

// --- データベース本体 ---
// ★ここに Templates を追加するのを忘れずに！
@DriftDatabase(tables: [Accounts, Transactions, Templates]) 
class MyDatabase extends _$MyDatabase {
  MyDatabase() : super(_openConnection());

  // ★バージョンを3にする
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
        // ★バージョン3でTemplatesテーブルを作成
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

  // --- ★Templates (New!) ---
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

  // 初期データ投入
  Future<void> seedDefaultAccounts() async {
    final allAccounts = await getAllAccounts();
    if (allAccounts.isEmpty) {
      await addAccount('現金', 'asset', null);
      await addAccount('銀行口座', 'asset', null);
      await addAccount('クレジットカード', 'liability', null);
      await addAccount('食費', 'expense', 50000);
      await addAccount('日用品', 'expense', 10000);
      await addAccount('交通費', 'expense', 10000);
      await addAccount('給料', 'income', null);
      await addAccount('その他', 'expense', 10000);
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