import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../database.dart';

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

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadData();
  }

  Future<void> _loadData() async {
    final txs = await widget.db.getTransactions();
    final acs = await widget.db.getAllAccounts();
    
    // 取引を「日付ごと」にグループ化する
    Map<DateTime, List<Transaction>> events = {};
    for (var t in txs) {
      // 時間情報を切り捨てて「年月日」だけにする
      final date = DateTime(t.date.year, t.date.month, t.date.day);
      if (events[date] == null) {
        events[date] = [];
      }
      events[date]!.add(t);
    }

    setState(() {
      _events = events;
      _accounts = acs;
      // 起動時は「今日」のデータを選択状態にする
      _selectedEvents = _getEventsForDay(_selectedDay!);
    });
  }

  // 指定した日のデータを取り出す関数
  List<Transaction> _getEventsForDay(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return _events[date] ?? [];
  }

  // 科目名を取得する便利関数
  String _getAccountName(int id) {
    return _accounts.firstWhere((a) => a.id == id, orElse: () => const Account(id: -1, name: '不明', type: '', costType: 'variable')).name;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fmt = NumberFormat("#,###");

    return Scaffold(
      body: Column(
        children: [
          // 1. カレンダー本体
          Card(
            margin: const EdgeInsets.all(8.0),
            elevation: 2,
            child: TableCalendar<Transaction>(
              locale: 'ja_JP', // 日本語化
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              
              // イベント（取引）の読み込み設定
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

              // デザイン設定
              headerStyle: const HeaderStyle(
                formatButtonVisible: false, // 「2週間/1週間」切り替えボタンを消す
                titleCentered: true,
              ),
              calendarStyle: CalendarStyle(
                // 今日のデザイン
                todayDecoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                // 選んだ日のデザイン
                selectedDecoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                // イベントがある日のドットマーカー
                markerDecoration: BoxDecoration(
                  color: colorScheme.error,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),

          const Divider(height: 1),

          // 2. 選んだ日の収支合計
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('yyyy/MM/dd (E)', 'ja').format(_selectedDay!),
                  style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                ),
                Text(
                  '合計: ${fmt.format(_selectedEvents.fold(0, (sum, t) => sum + t.amount))}円',
                  style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary),
                ),
              ],
            ),
          ),

          // 3. 明細リスト
          Expanded(
            child: _selectedEvents.isEmpty
                ? Center(
                    child: Text(
                      '取引なし\n(ノーマネーデー達成！🎉)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.outline),
                    ),
                  )
                : ListView.builder(
                    itemCount: _selectedEvents.length,
                    itemBuilder: (context, index) {
                      final t = _selectedEvents[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: colorScheme.primaryContainer,
                          child: Icon(Icons.receipt_long, size: 18, color: colorScheme.onPrimaryContainer),
                        ),
                        title: Text(_getAccountName(t.debitAccountId)), // 借方（使った内容）
                        subtitle: Text('${_getAccountName(t.creditAccountId)}払い'), // 貸方（支払い元）
                        trailing: Text(
                          '¥${fmt.format(t.amount)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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