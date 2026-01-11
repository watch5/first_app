import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../database.dart';
import 'add_transaction_page.dart'; // ★追加: 編集画面用

class CalendarPage extends StatefulWidget {
  final MyDatabase db;
  const CalendarPage({super.key, required this.db});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  // カレンダーの設定
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // データ
  Map<DateTime, List<Transaction>> _events = {};
  List<Transaction> _selectedEvents = [];
  List<Account> _accounts = [];
  Map<DateTime, int> _budgets = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadData();
  }

  Future<void> _loadData() async {
    final txs = await widget.db.getTransactions();
    final acs = await widget.db.getAllAccounts();
    final budgetsList = await widget.db.getDailyBudgets(DateTime(2020), DateTime(2030));
    
    Map<DateTime, List<Transaction>> events = {};
    for (var t in txs) {
      final date = DateTime(t.date.year, t.date.month, t.date.day);
      if (events[date] == null) {
        events[date] = [];
      }
      events[date]!.add(t);
    }

    Map<DateTime, int> budgetMap = {};
    for (var b in budgetsList) {
       final date = DateTime(b.date.year, b.date.month, b.date.day);
       budgetMap[date] = b.amount;
    }

    setState(() {
      _events = events;
      _accounts = acs;
      _budgets = budgetMap;
      // データ更新後、現在選択中の日のリストも更新
      if (_selectedDay != null) {
        _selectedEvents = _getEventsForDay(_selectedDay!);
      }
    });
  }

  List<Transaction> _getEventsForDay(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return _events[date] ?? [];
  }

  String _getAccountName(int id) {
    return _accounts.firstWhere((a) => a.id == id, orElse: () => const Account(id: -1, name: '不明', type: '', costType: 'variable')).name;
  }

  // --- ★追加: 取引編集機能 ---
  Future<void> _editTransaction(Transaction t) async {
    // AddTransactionPage を開く
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => AddTransactionPage(
        accounts: _accounts, 
        db: widget.db,
        transaction: t, // 既存データを渡す
      )),
    );

    // 修正されて戻ってきた場合
    if (result != null && result.containsKey('id')) {
      await widget.db.updateTransaction(
        result['id'],
        result['debitId'],
        result['creditId'],
        result['amount'],
        result['date'],
      );
      // 画面更新
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('修正しました！')));
      }
    }
  }

  // --- ★追加: 予算設定機能 ---
  Future<void> _editBudget() async {
    if (_selectedDay == null) return;
    final date = DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
    final currentBudget = _budgets[date] ?? 2000;

    final controller = TextEditingController(text: currentBudget.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${DateFormat('M/d').format(date)} の予算設定'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(suffixText: '円', labelText: '目標金額'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result != null) {
      await widget.db.setDailyBudget(date, result);
      _loadData(); // 再描画
    }
  }

  Widget? _buildMarker(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(day.year, day.month, day.day);
    if (date.isAfter(today)) return null;

    final txs = _getEventsForDay(date);
    int expense = 0;
    final expenseIds = _accounts.where((a) => a.type == 'expense').map((a) => a.id).toList();
    
    for (var t in txs) {
       if (expenseIds.contains(t.debitAccountId)) expense += t.amount;
       if (expenseIds.contains(t.creditAccountId)) expense -= t.amount; 
    }

    final budget = _budgets[date] ?? 2000;

    if (expense == 0) {
      return const Icon(Icons.sentiment_very_satisfied, color: Colors.amber, size: 14);
    } else if (expense <= budget) {
      return const Icon(Icons.thumb_up, color: Colors.teal, size: 14);
    }
    return null;
  }

  Widget _buildCell(BuildContext context, DateTime day, {required bool isSelected, required bool isToday}) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = day.day.toString();
    
    BoxDecoration? decoration;
    TextStyle? textStyle;

    if (isSelected) {
      decoration = BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle);
      textStyle = const TextStyle(color: Colors.white, fontWeight: FontWeight.bold);
    } else if (isToday) {
      decoration = BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.3), shape: BoxShape.circle);
      textStyle = TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold);
    } else {
      if (day.weekday == DateTime.sunday) {
        textStyle = const TextStyle(color: Colors.red);
      } else if (day.weekday == DateTime.saturday) {
        textStyle = const TextStyle(color: Colors.blue);
      } else {
        textStyle = TextStyle(color: colorScheme.onSurface);
      }
    }

    final marker = _buildMarker(day);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.all(4.0), // マージンを少し減らしてセルを広く
      decoration: decoration,
      child: Stack(
        children: [
          // ★修正: 数字を少し上に配置
          Positioned(
            top: 6,
            left: 0,
            right: 0,
            child: Center(child: Text(text, style: textStyle)),
          ),
          // ★修正: マークを確実に下に配置（これで被らない）
          if (marker != null)
            Positioned(
              bottom: 4,
              left: 0,
              right: 0,
              child: Center(child: marker),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fmt = NumberFormat("#,###");

    // 選択された日の予算
    final selectedDateOnly = _selectedDay != null 
        ? DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day) 
        : DateTime.now();
    final currentBudget = _budgets[selectedDateOnly] ?? 2000;

    return Scaffold(
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(8.0),
            elevation: 2,
            child: TableCalendar<Transaction>(
              locale: 'ja_JP',
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              daysOfWeekHeight: 30,
              rowHeight: 60, // ★修正: セルの高さを少し広げて、上下の配置に余裕を持たせる
              
              eventLoader: _getEventsForDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                if (!isSameDay(_selectedDay, selectedDay)) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                    _selectedEvents = _getEventsForDay(selectedDay);
                  });
                }
              },
              onFormatChanged: (format) {
                if (_calendarFormat != format) setState(() => _calendarFormat = format);
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
              },
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
              ),
              calendarBuilders: CalendarBuilders(
                selectedBuilder: (context, day, focusedDay) => 
                  _buildCell(context, day, isSelected: true, isToday: isSameDay(day, DateTime.now())),
                todayBuilder: (context, day, focusedDay) => 
                  _buildCell(context, day, isSelected: false, isToday: true),
                defaultBuilder: (context, day, focusedDay) => 
                  _buildCell(context, day, isSelected: false, isToday: false),
              ),
            ),
          ),

          const Divider(height: 1),

          // --- 合計＆予算バー ---
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            child: Row(
              children: [
                // 日付
                Text(
                  DateFormat('M/d(E)', 'ja').format(_selectedDay!),
                  style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface, fontSize: 16),
                ),
                const Spacer(),
                
                // 合計
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '合計 ${fmt.format(_selectedEvents.fold(0, (sum, t) => sum + t.amount))}円',
                      style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary, fontSize: 16),
                    ),
                    // ★追加: 予算設定ボタン
                    InkWell(
                      onTap: _editBudget,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '予算: ${fmt.format(currentBudget)}',
                            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.edit, size: 12, color: colorScheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // --- 明細リスト ---
          Expanded(
            child: _selectedEvents.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '取引なし',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.outline),
                        ),
                        const SizedBox(height: 10),
                        const Text('🎉 ノーマネーデー達成！ 🎉'),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _selectedEvents.length,
                    itemBuilder: (context, index) {
                      final t = _selectedEvents[index];
                      return ListTile(
                        // ★追加: タップで編集へ
                        onTap: () => _editTransaction(t),
                        leading: CircleAvatar(
                          backgroundColor: colorScheme.primaryContainer,
                          child: Icon(Icons.receipt_long, size: 18, color: colorScheme.onPrimaryContainer),
                        ),
                        title: Text(_getAccountName(t.debitAccountId)),
                        subtitle: Text('${_getAccountName(t.creditAccountId)}払い'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '¥${fmt.format(t.amount)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right, size: 16, color: colorScheme.outline),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}