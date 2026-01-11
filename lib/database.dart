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
  // 固定費(fixed)か変動費(variable)か。デフォルトはvariable
  TextColumn get costType => text().withDefault(const Constant('variable'))(); 
}

// --- 2. 取引明細テーブル ---
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get debitAccountId => integer()();
  IntColumn get creditAccountId => integer()();
  IntColumn get amount => integer()();
  DateTimeColumn get date => dateTime()();
  // ★追加: 自動連携フラグ (true=自動, false=手動)
  BoolColumn get isAuto => boolean().withDefault(const Constant(false))();
}

// --- 3. テンプレートテーブル ---
class Templates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); 
  IntColumn get debitAccountId => integer()();
  IntColumn get creditAccountId => integer()();
  IntColumn get amount => integer()();
}

// --- 4. 日別予算テーブル ---
class DailyBudgets extends Table {
  DateTimeColumn get date => dateTime()(); // 日付
  IntColumn get amount => integer()();     // その日の予算（食費などの変動費）
  
  @override
  Set<Column> get primaryKey => {date};    // 日付を一意のキーにする
}

// --- 5. 繰り返し取引（固定費・サブスク）テーブル ---
class RecurringTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); // "家賃", "Netflix" など
  IntColumn get dayOfMonth => integer()(); // 毎月何日 (1-31)
  IntColumn get debitAccountId => integer()();
  IntColumn get creditAccountId => integer()();
  IntColumn get amount => integer()();
}

// --- データベース本体 ---
@DriftDatabase(tables: [Accounts, Transactions, Templates, DailyBudgets, RecurringTransactions]) 
class MyDatabase extends _$MyDatabase {
  MyDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 7; // ★バージョンを 7 に更新

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
      if (from < 4) {
        await m.addColumn(accounts, accounts.costType);
      }
      if (from < 5) {
        await m.createTable(dailyBudgets);
      }
      if (from < 6) {
        await m.createTable(recurringTransactions);
      }
      // ★バージョン7への移行処理 (isAuto列を追加)
      if (from < 7) {
        await m.addColumn(transactions, transactions.isAuto);
      }
    },
  );

  // --- クエリ群 ---

  // === Accounts ===
  Future<List<Account>> getAllAccounts() => select(accounts).get();
  
  Future<int> addAccount(String name, String type, int? budget, String costType) {
    return into(accounts).insert(AccountsCompanion(
      name: Value(name),
      type: Value(type),
      monthlyBudget: Value(budget),
      costType: Value(costType),
    ));
  }
  
  Future<void> updateAccountCostType(int id, String costType) {
    return (update(accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(costType: Value(costType)),
    );
  }

  Future<void> updateAccountBudget(int id, int budget) {
    return (update(accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(monthlyBudget: Value(budget)),
    );
  }
  
  Future<void> deleteAccount(int id) {
    return transaction(() async {
      await (delete(transactions)..where((t) => 
        t.debitAccountId.equals(id) | t.creditAccountId.equals(id)
      )).go();
      await (delete(accounts)..where((a) => a.id.equals(id))).go();
    });
  }

  // === Transactions ===
  Future<List<Transaction>> getTransactions() => select(transactions).get();
  
  // ★変更: isAuto引数を追加 (デフォルトはfalse)
  Future<int> addTransaction(int debitId, int creditId, int amount, DateTime date, {bool isAuto = false}) {
    return into(transactions).insert(TransactionsCompanion(
      debitAccountId: Value(debitId),
      creditAccountId: Value(creditId),
      amount: Value(amount),
      date: Value(date),
      isAuto: Value(isAuto), // ★DBに保存
    ));
  }
  
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

  Future<void> deleteTransaction(int id) {
    return (delete(transactions)..where((t) => t.id.equals(id))).go();
  }

  // === Templates ===
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

  // === AI予測機能 ===
  Future<int?> getMostFrequentCreditId(int debitId) async {
    final result = await customSelect(
      'SELECT credit_account_id, COUNT(*) as cnt '
      'FROM transactions '
      'WHERE debit_account_id = ? '
      'GROUP BY credit_account_id '
      'ORDER BY cnt DESC '
      'LIMIT 1',
      variables: [Variable.withInt(debitId)],
      readsFrom: {transactions}, 
    ).get();

    if (result.isNotEmpty) {
      return result.first.read<int>('credit_account_id');
    }
    return null;
  }

  // === 資金繰り・日別予算機能 ===

  Future<List<DailyBudget>> getDailyBudgets(DateTime start, DateTime end) {
    return (select(dailyBudgets)
      ..where((t) => t.date.isBetweenValues(start, end))
      ..orderBy([(t) => OrderingTerm(expression: t.date)])
    ).get();
  }

  Future<void> setDailyBudget(DateTime date, int amount) {
    return into(dailyBudgets).insertOnConflictUpdate(DailyBudgetsCompanion(
      date: Value(date),
      amount: Value(amount),
    ));
  }
  
  Future<List<Transaction>> getFutureTransactions(DateTime start, DateTime end) {
     return (select(transactions)
      ..where((t) => t.date.isBetweenValues(start, end))
    ).get();
  }
  
  Future<int> getCurrentAssetBalance() async {
    final assetAccounts = await (select(accounts)..where((a) => a.type.equals('asset'))).get();
    if (assetAccounts.isEmpty) return 0;
    
    final assetIds = assetAccounts.map((a) => a.id).toList();
    
    final txs = await select(transactions).get();
    int total = 0;
    for (var t in txs) {
      if (assetIds.contains(t.debitAccountId)) total += t.amount;
      if (assetIds.contains(t.creditAccountId)) total -= t.amount;
    }
    return total;
  }

  // === 繰り返し取引（固定費・サブスク）機能 ===
  Future<List<RecurringTransaction>> getAllRecurringTransactions() => select(recurringTransactions).get();
  
  Future<int> addRecurringTransaction(String name, int day, int debitId, int creditId, int amount) {
    return into(recurringTransactions).insert(RecurringTransactionsCompanion(
      name: Value(name),
      dayOfMonth: Value(day),
      debitAccountId: Value(debitId),
      creditAccountId: Value(creditId),
      amount: Value(amount),
    ));
  }

  Future<void> deleteRecurringTransaction(int id) {
    return (delete(recurringTransactions)..where((t) => t.id.equals(id))).go();
  }

  // === 初期データ・デバッグデータ投入 ===

  Future<void> seedDefaultAccounts() async {
    final allAccounts = await getAllAccounts();
    if (allAccounts.isEmpty) {
      // --- 資産 (Assets) ---
      await addAccount('現金', 'asset', null, 'variable');
      await addAccount('銀行口座', 'asset', null, 'variable');
      await addAccount('PayPay', 'asset', null, 'variable');
      await addAccount('Suica/PASMO', 'asset', null, 'variable');

      // --- 負債 (Liabilities) ---
      await addAccount('クレジットカード', 'liability', null, 'variable');
      
      // --- 収益 (Income) ---
      await addAccount('給料', 'income', null, 'variable');
      await addAccount('ボーナス', 'income', null, 'variable');
      await addAccount('臨時収入', 'income', null, 'variable');

      // --- 費用 (Expenses) ---
      await addAccount('家賃', 'expense', 70000, 'fixed');
      await addAccount('電気代', 'expense', 5000, 'fixed');
      await addAccount('ガス代', 'expense', 4000, 'fixed');
      await addAccount('水道代', 'expense', 3000, 'fixed');
      await addAccount('通信費', 'expense', 5000, 'fixed'); 
      
      await addAccount('食費', 'expense', 30000, 'variable');
      await addAccount('外食', 'expense', 10000, 'variable');
      await addAccount('日用品', 'expense', 5000, 'variable');
      await addAccount('交通費', 'expense', 10000, 'variable');
      await addAccount('衣服・美容', 'expense', 10000, 'variable');
      await addAccount('交際費', 'expense', 10000, 'variable');
      await addAccount('医療費', 'expense', 5000, 'variable');
      await addAccount('趣味・娯楽', 'expense', 10000, 'variable');
      await addAccount('その他', 'expense', 5000, 'variable');
    }
  }

  Future<void> seedDebugData() async {
    final tx = await getTransactions();
    if (tx.isNotEmpty) return; 

    final allAccounts = await getAllAccounts();
    
    int getId(String name) {
      try {
        return allAccounts.firstWhere((a) => a.name == name).id;
      } catch (e) {
        return allAccounts.isNotEmpty ? allAccounts.first.id : 0;
      }
    }

    final now = DateTime.now();
    DateTime date(int day, {int monthOffset = 0}) {
      return DateTime(now.year, now.month + monthOffset, day);
    }

    await batch((batch) {
      // ... (既存のデバッグデータは isAuto 指定なし＝false でOK)
      batch.insert(transactions, TransactionsCompanion.insert(
        debitAccountId: getId('銀行口座'), creditAccountId: getId('給料'),
        amount: 280000, date: date(25, monthOffset: -1),
      ));
      // ... (以下略、長くなるので省略しますが既存のままでOKです)
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}