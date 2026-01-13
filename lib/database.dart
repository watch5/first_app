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

// ★追加: 減価償却ペット（固定資産）
class AssetPet {
  final int id;
  final String name;       // ペット名（資産名）
  final int price;         // 購入価格
  final DateTime purchaseDate; // 購入日（誕生日）
  final int lifeYears;     // 耐用年数（寿命）
  final int characterType; // 0:ロボ, 1:犬, 2:猫...（見た目）

  AssetPet({
    required this.id,
    required this.name,
    required this.price,
    required this.purchaseDate,
    required this.lifeYears,
    required this.characterType,
  });

  // 現在の価値（HP）を計算
  int get currentValue {
    final now = DateTime.now();
    // 日単位で経過を計算
    final daysPassed = now.difference(purchaseDate).inDays;
    final totalDays = lifeYears * 365;
    
    if (daysPassed < 0) return price; // 未来の日付なら新品
    if (daysPassed >= totalDays) return 1; // 償却完了（備忘価額1円）

    // 定額法で計算
    final depreciation = (price / totalDays) * daysPassed;
    return (price - depreciation).toInt();
  }

  // 元気度（0.0 〜 1.0）
  double get healthRatio {
     if (price == 0) return 0;
     // 1円（引退）なら0
     if (currentValue <= 1) return 0.0;
     return (currentValue / price).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'purchase_date': purchaseDate.toIso8601String(),
      'life_years': lifeYears,
      'character_type': characterType,
    };
  }

  static AssetPet fromMap(Map<String, dynamic> map) {
    return AssetPet(
      id: map['id'],
      name: map['name'],
      price: map['price'],
      purchaseDate: DateTime.parse(map['purchase_date']),
      lifeYears: map['life_years'],
      characterType: map['character_type'],
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
    // バージョンを4に上げて再作成を強制
    return await openDatabase(
      path,
      version: 4, 
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // 開発中なので簡易的に全再作成
        if (oldVersion < 4) {
          await db.execute('DROP TABLE IF EXISTS accounts');
          await db.execute('DROP TABLE IF EXISTS transactions');
          await db.execute('DROP TABLE IF EXISTS recurring_transactions');
          await db.execute('DROP TABLE IF EXISTS templates');
          await db.execute('DROP TABLE IF EXISTS daily_budgets');
          await db.execute('DROP TABLE IF EXISTS asset_pets'); // 追加
          await _createTables(db);
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
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
    await db.execute('''
      CREATE TABLE templates(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        debit_account_id INTEGER,
        credit_account_id INTEGER,
        amount INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE daily_budgets(
        date TEXT PRIMARY KEY,
        amount INTEGER
      )
    ''');
    // ★追加: ペットテーブル
    await db.execute('''
      CREATE TABLE asset_pets(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        price INTEGER,
        purchase_date TEXT,
        life_years INTEGER,
        character_type INTEGER
      )
    ''');
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

  Future<List<Transaction>> getFutureTransactions(DateTime start, DateTime end) async {
    final db = await database;
    return []; 
  }

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

  // --- Recurring Transactions ---
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

  // --- Templates ---
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

  // --- Daily Budgets ---
  Future<List<DailyBudget>> getDailyBudgets(DateTime start, DateTime end) async {
    final db = await database;
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

  // --- ★追加: Asset Pets (固定資産) ---
  Future<List<AssetPet>> getAllAssetPets() async {
    final db = await database;
    final res = await db.query('asset_pets');
    return res.map((m) => AssetPet.fromMap(m)).toList();
  }

  Future<void> addAssetPet(String name, int price, DateTime purchaseDate, int lifeYears, int characterType) async {
    final db = await database;
    await db.insert('asset_pets', {
      'name': name,
      'price': price,
      'purchase_date': purchaseDate.toIso8601String(),
      'life_years': lifeYears,
      'character_type': characterType,
    });
  }

  Future<void> deleteAssetPet(int id) async {
    final db = await database;
    await db.delete('asset_pets', where: 'id = ?', whereArgs: [id]);
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

  Future<void> seedDebugData() async {
    final txs = await getTransactions();
    if (txs.isNotEmpty) return; 

    final now = DateTime.now();
    
    // 1. 先月の給料
    await addTransaction(2, 14, 250000, DateTime(now.year, now.month - 1, 25), note: '10月分給料');
    // 2. 先月の家賃
    await addTransaction(13, 2, 80000, DateTime(now.year, now.month - 1, 27), note: '10月分家賃');
    // 3. 今月の給料
    await addTransaction(2, 14, 250000, DateTime(now.year, now.month, 25), note: '11月分給料');

    // 4. 日々の買い物
    await addTransaction(10, 1, 1200, DateTime(now.year, now.month, now.day - 5), note: 'ランチ');
    await addTransaction(10, 1, 850, DateTime(now.year, now.month, now.day - 3), note: 'カフェ');
    await addTransaction(10, 1, 3500, DateTime(now.year, now.month, now.day - 1), note: '飲み会');
    await addTransaction(11, 2, 5000, DateTime(now.year, now.month, now.day - 10), note: 'Amazon');

    // 5. 予算設定
    await updateAccountBudget(10, 30000);
    await setDailyBudget(DateTime(now.year, now.month, now.day), 2000);

    // ★追加: テスト用のペット（資産）も作っておく
    await addAssetPet('MacBook Pro', 300000, DateTime(now.year, now.month - 3, 1), 4, 0); // 3ヶ月前のPC
    await addAssetPet('社用車', 1500000, DateTime(now.year - 2, 1, 1), 6, 1); // 2年前の車
  }
}