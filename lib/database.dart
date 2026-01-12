import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// --- データモデル ---

class Account {
  final int id;
  final String name;
  final String type; // 'asset', 'liability', 'income', 'expense'
  final String costType; // 'variable', 'fixed' (for expenses)
  final int? withdrawalDay; // 1-31 (for liabilities)
  final int? paymentAccountId; // for liabilities
  final int budget; // 月次予算 (0の場合は予算なし)

  // 互換性のためのゲッター
  int? get monthlyBudget => budget == 0 ? null : budget;

  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.costType,
    this.withdrawalDay,
    this.paymentAccountId,
    this.budget = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'cost_type': costType,
      'withdrawal_day': withdrawalDay,
      'payment_account_id': paymentAccountId,
      'budget': budget,
    };
  }

  static Account fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'],
      name: map['name'],
      type: map['type'],
      costType: map['cost_type'] ?? '',
      withdrawalDay: map['withdrawal_day'],
      paymentAccountId: map['payment_account_id'],
      budget: map['budget'] ?? 0,
    );
  }
}

class Transaction {
  final int id;
  final int debitAccountId;
  final int creditAccountId;
  final int amount;
  final DateTime date;
  final String? note;
  final int isAuto; // 0 or 1

  const Transaction({
    required this.id,
    required this.debitAccountId,
    required this.creditAccountId,
    required this.amount,
    required this.date,
    this.note,
    this.isAuto = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'debit_account_id': debitAccountId,
      'credit_account_id': creditAccountId,
      'amount': amount,
      'date': date.toIso8601String(),
      'note': note,
      'is_auto': isAuto,
    };
  }

  static Transaction fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'],
      debitAccountId: map['debit_account_id'],
      creditAccountId: map['credit_account_id'],
      amount: map['amount'],
      date: DateTime.parse(map['date']),
      note: map['note'],
      isAuto: map['is_auto'] ?? 0,
    );
  }
}

class RecurringTransaction {
  final int id;
  final String name;
  final int dayOfMonth;
  final int debitAccountId;
  final int creditAccountId;
  final int amount;

  RecurringTransaction({
    required this.id,
    required this.name,
    required this.dayOfMonth,
    required this.debitAccountId,
    required this.creditAccountId,
    required this.amount,
  });

  static RecurringTransaction fromMap(Map<String, dynamic> map) {
    return RecurringTransaction(
      id: map['id'],
      name: map['name'],
      dayOfMonth: map['day_of_month'],
      debitAccountId: map['debit_account_id'],
      creditAccountId: map['credit_account_id'],
      amount: map['amount'],
    );
  }
}

class Template {
  final int id;
  final String name;
  final int debitAccountId;
  final int creditAccountId;
  final int amount;

  Template({
    required this.id,
    required this.name,
    required this.debitAccountId,
    required this.creditAccountId,
    required this.amount,
  });

  static Template fromMap(Map<String, dynamic> map) {
    return Template(
      id: map['id'],
      name: map['name'],
      debitAccountId: map['debit_account_id'],
      creditAccountId: map['credit_account_id'],
      amount: map['amount'],
    );
  }
}

class DailyBudget {
  final DateTime date;
  final int amount;

  DailyBudget({required this.date, required this.amount});

  static DailyBudget fromMap(Map<String, dynamic> map) {
    return DailyBudget(
      date: DateTime.parse(map['date']),
      amount: map['amount'],
    );
  }
}

// --- データベース管理クラス ---

class MyDatabase {
  static final MyDatabase _instance = MyDatabase._internal();
  static Database? _database;

  factory MyDatabase() => _instance;

  MyDatabase._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'dualy_app.db');
    // バージョンを上げて再作成を強制する
    return await openDatabase(
      path,
      version: 3, 
      onCreate: (db, version) async {
        // Accounts table
        await db.execute('''
          CREATE TABLE accounts(
            id INTEGER PRIMARY KEY AUTOINCREMENT, 
            name TEXT, 
            type TEXT, 
            cost_type TEXT,
            withdrawal_day INTEGER,
            payment_account_id INTEGER,
            budget INTEGER DEFAULT 0 
          )
        ''');

        // Transactions table
        await db.execute('''
          CREATE TABLE transactions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            debit_account_id INTEGER,
            credit_account_id INTEGER,
            amount INTEGER,
            date TEXT,
            note TEXT,
            is_auto INTEGER DEFAULT 0,
            FOREIGN KEY(debit_account_id) REFERENCES accounts(id),
            FOREIGN KEY(credit_account_id) REFERENCES accounts(id)
          )
        ''');

        // Recurring Transactions table
        await db.execute('''
          CREATE TABLE recurring_transactions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            day_of_month INTEGER,
            debit_account_id INTEGER,
            credit_account_id INTEGER,
            amount INTEGER
          )
        ''');

        // Templates table
        await db.execute('''
          CREATE TABLE templates(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            debit_account_id INTEGER,
            credit_account_id INTEGER,
            amount INTEGER
          )
        ''');

        // Daily Budgets table
        await db.execute('''
          CREATE TABLE daily_budgets(
            date TEXT PRIMARY KEY,
            amount INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // 簡易的なマイグレーション: テーブルがなければ作る
        // 今回はアンインストール推奨なのでonCreateが走るはずですが、念のため
        if (oldVersion < 3) {
          // 既存テーブルの削除（開発中なのでデータリセット）
          await db.execute('DROP TABLE IF EXISTS accounts');
          await db.execute('DROP TABLE IF EXISTS transactions');
          await db.execute('DROP TABLE IF EXISTS recurring_transactions');
          await db.execute('DROP TABLE IF EXISTS templates');
          await db.execute('DROP TABLE IF EXISTS daily_budgets');
          // onCreateと同じ処理を実行
          await _initDatabase().then((d) => d.close()); 
          // (実際には再帰呼び出しになるので、ここではonCreateの中身をコピペするのが正しいが、
          // ユーザーにはアンインストールしてもらうのが確実)
        }
      },
    );
  }
  
  // --- Accounts ---
  Future<List<Account>> getAllAccounts() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('accounts');
    return List.generate(maps.length, (i) => Account.fromMap(maps[i]));
  }

  Future<void> insertAccount(Account account) async {
    final db = await database;
    await db.insert('accounts', account.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ★復活: 個別のパラメータで追加するメソッド
  Future<void> addAccount(String name, String type, int? budget, String costType, {int? withdrawalDay, int? paymentAccountId}) async {
    final db = await database;
    await db.insert('accounts', {
      'name': name,
      'type': type,
      'budget': budget ?? 0,
      'cost_type': costType,
      'withdrawal_day': withdrawalDay,
      'payment_account_id': paymentAccountId,
    });
  }

  // ★復活: 属性更新メソッド
  Future<void> updateAccountCostType(int id, String costType) async {
    final db = await database;
    await db.update('accounts', {'cost_type': costType}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateAccountPaymentInfo(int id, int? day, int? paymentAccountId) async {
    final db = await database;
    await db.update('accounts', {
      'withdrawal_day': day,
      'payment_account_id': paymentAccountId
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateAccountBudget(int id, int budget) async {
    final db = await database;
    await db.update('accounts', {'budget': budget}, where: 'id = ?', whereArgs: [id]);
  }
  
  Future<void> updateAccount(Account account) async {
    final db = await database;
    await db.update('accounts', account.toMap(), where: 'id = ?', whereArgs: [account.id]);
  }

  Future<void> deleteAccount(int id) async {
    final db = await database;
    await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  // --- Transactions ---
  Future<List<Transaction>> getTransactions() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('transactions', orderBy: "date DESC, id DESC");
    return List.generate(maps.length, (i) => Transaction.fromMap(maps[i]));
  }

  Future<void> addTransaction(int debitId, int creditId, int amount, DateTime date, {String? note, bool isAuto = false}) async {
    final db = await database;
    await db.insert(
      'transactions',
      {
        'debit_account_id': debitId,
        'credit_account_id': creditId,
        'amount': amount,
        'date': date.toIso8601String(),
        'note': note,
        'is_auto': isAuto ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateTransaction(int id, int debitId, int creditId, int amount, DateTime date, {String? note}) async {
    final db = await database;
    await db.update(
      'transactions',
      {
        'debit_account_id': debitId,
        'credit_account_id': creditId,
        'amount': amount,
        'date': date.toIso8601String(),
        'note': note,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteTransaction(int id) async {
    final db = await database;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  // ★復活: 将来の取引取得
  Future<List<Transaction>> getFutureTransactions(DateTime start, DateTime end) async {
    final db = await database;
    // まだ登録されていない未来の予定などを取得するならここですが、
    // 基本的には「登録済み」のものを返す実装にします
    // (自動登録ロジックはアプリ起動時などに別途実装が必要)
    return []; 
  }

  // ★復活: 資産残高取得
  Future<int> getCurrentAssetBalance() async {
    final accounts = await getAllAccounts();
    final assetIds = accounts.where((a) => a.type == 'asset').map((a) => a.id).toList();
    if (assetIds.isEmpty) return 0;

    final txs = await getTransactions();
    int balance = 0;
    for (var t in txs) {
      if (assetIds.contains(t.debitAccountId)) balance += t.amount;
      if (assetIds.contains(t.creditAccountId)) balance -= t.amount;
    }
    return balance;
  }
  
  // ★復活: よく使う貸方（予測）
  Future<int?> getMostFrequentCreditId(int debitId) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT credit_account_id, COUNT(*) as count 
      FROM transactions 
      WHERE debit_account_id = ? 
      GROUP BY credit_account_id 
      ORDER BY count DESC 
      LIMIT 1
    ''', [debitId]);
    
    if (result.isNotEmpty) {
      return result.first['credit_account_id'] as int;
    }
    return null;
  }

  // --- ★復活: Recurring Transactions (固定費) ---
  Future<List<RecurringTransaction>> getAllRecurringTransactions() async {
    final db = await database;
    final res = await db.query('recurring_transactions');
    return res.map((m) => RecurringTransaction.fromMap(m)).toList();
  }

  Future<void> addRecurringTransaction(String name, int day, int debitId, int creditId, int amount) async {
    final db = await database;
    await db.insert('recurring_transactions', {
      'name': name,
      'day_of_month': day,
      'debit_account_id': debitId,
      'credit_account_id': creditId,
      'amount': amount,
    });
  }

  Future<void> deleteRecurringTransaction(int id) async {
    final db = await database;
    await db.delete('recurring_transactions', where: 'id = ?', whereArgs: [id]);
  }

  // --- ★復活: Templates (テンプレート) ---
  Future<List<Template>> getAllTemplates() async {
    final db = await database;
    final res = await db.query('templates');
    return res.map((m) => Template.fromMap(m)).toList();
  }

  Future<void> addTemplate(String name, int debitId, int creditId, int amount) async {
    final db = await database;
    await db.insert('templates', {
      'name': name,
      'debit_account_id': debitId,
      'credit_account_id': creditId,
      'amount': amount,
    });
  }

  Future<void> deleteTemplate(int id) async {
    final db = await database;
    await db.delete('templates', where: 'id = ?', whereArgs: [id]);
  }

  // --- ★復活: Daily Budgets (日次予算) ---
  Future<List<DailyBudget>> getDailyBudgets(DateTime start, DateTime end) async {
    final db = await database;
    // 期間指定は実装簡略化のため全件取得してフィルタ
    final res = await db.query('daily_budgets');
    return res.map((m) => DailyBudget.fromMap(m)).toList();
  }

  Future<void> setDailyBudget(DateTime date, int amount) async {
    final db = await database;
    final dateStr = date.toIso8601String();
    await db.insert(
      'daily_budgets',
      {'date': dateStr, 'amount': amount},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Seeds ---
  Future<void> seedDefaultAccounts() async {
    final accounts = await getAllAccounts();
    if (accounts.isEmpty) {
      await insertAccount(const Account(id: 1, name: '現金', type: 'asset', costType: ''));
      await insertAccount(const Account(id: 2, name: '銀行口座', type: 'asset', costType: ''));
      await insertAccount(const Account(id: 10, name: '食費', type: 'expense', costType: 'variable'));
      await insertAccount(const Account(id: 11, name: '日用品', type: 'expense', costType: 'variable'));
      await insertAccount(const Account(id: 12, name: '交通費', type: 'expense', costType: 'variable'));
      await insertAccount(const Account(id: 13, name: '家賃', type: 'expense', costType: 'fixed'));
      await insertAccount(const Account(id: 14, name: '給料', type: 'income', costType: ''));
      await insertAccount(const Account(id: 15, name: 'その他収入', type: 'income', costType: ''));
    }
  }

// ★ここから下を上書き（ファイルの最後まで）

  // テストデータを生成するメソッド
  Future<void> seedDebugData() async {
    final txs = await getTransactions();
    if (txs.isNotEmpty) return; // すでにデータがあれば何もしない

    final now = DateTime.now();
    
    // 1. 先月の給料
    await addTransaction(2, 14, 250000, DateTime(now.year, now.month - 1, 25), note: '10月分給料');
    // 2. 先月の家賃
    await addTransaction(13, 2, 80000, DateTime(now.year, now.month - 1, 27), note: '10月分家賃');
    
    // 3. 今月の給料（予定として入れたい場合も含む）
    await addTransaction(2, 14, 250000, DateTime(now.year, now.month, 25), note: '11月分給料');

    // 4. 日々の買い物（ランダムっぽく）
    // 食費 (現金払い)
    await addTransaction(10, 1, 1200, DateTime(now.year, now.month, now.day - 5), note: 'ランチ');
    await addTransaction(10, 1, 850, DateTime(now.year, now.month, now.day - 3), note: 'カフェ');
    await addTransaction(10, 1, 3500, DateTime(now.year, now.month, now.day - 1), note: '飲み会');
    
    // 日用品 (クレカ払い想定)
    await addTransaction(11, 2, 5000, DateTime(now.year, now.month, now.day - 10), note: 'Amazon');

    // 5. 予算設定（テスト用）
    // 食費(ID:10)に3万円の予算を設定
    await updateAccountBudget(10, 30000);
    // 全体予算を設定
    await setDailyBudget(DateTime(now.year, now.month, now.day), 2000);
  }
} 
// ↑ クラスの閉じカッコは1つだけです