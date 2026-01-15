import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart'; // 音声入力
import '../database.dart';
import 'add_transaction_page.dart';

class ReceiptScanPage extends StatefulWidget {
  final MyDatabase db;
  const ReceiptScanPage({super.key, required this.db});

  @override
  State<ReceiptScanPage> createState() => _ReceiptScanPageState();
}

class _ReceiptScanPageState extends State<ReceiptScanPage> with SingleTickerProviderStateMixin {
  // ★ここに取得したAPIキーを入れてください
  final String _apiKey = 'AIzaSyAjn7KgHXI8tx6lHGgmNiD7EsaaxTGWaXA';

  late TabController _tabController;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _textInputController = TextEditingController();
  
  // 音声入力用
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  String _lastWords = '';

  bool _isAnalyzing = false;
  String _status = '入力方法を選んでください';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initSpeech();
  }

  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Speech init error: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textInputController.dispose();
    super.dispose();
  }

  // --- Geminiによる解析処理 ---
  Future<void> _analyzeWithGemini({XFile? image, String? text}) async {
    setState(() {
      _isAnalyzing = true;
      _status = 'Geminiが思考中...🤖';
    });

    try {
      final accounts = await widget.db.getAllAccounts();
      final accountListStr = accounts.map((a) => "${a.id}:${a.name}(${a.type})").join(", ");

      // ★修正: 最新の安定版モデル 'gemini-2.5-flash' に変更
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _apiKey,
      );

      final basePrompt = """
        あなたは家計簿アプリの入力アシスタントです。
        提供された情報から取引情報を抽出し、JSON形式で返してください。

        【選択可能な科目リスト】
        $accountListStr

        【ルール】
        - 日付(date): yyyy-MM-dd形式。不明なら今日(${DateTime.now().toString().split(' ')[0]})。
        - 金額(amount): 整数。
        - 借方(debitId): 支出なら「食費」などのID。不明なら-1。
        - 貸方(creditId): 支払い元（現金、カードなど）のID。不明なら-1。
        - メモ(note): 店名や内容。
        - JSONキー: "date", "amount", "debitId", "creditId", "note"
        - 出力はJSONのみ。
      """;

      GenerateContentResponse response;

      if (image != null) {
        final imageBytes = await image.readAsBytes();
        final prompt = TextPart(basePrompt + "\n\nこの画像を解析してください。(レシートまたは決済画面のスクリーンショットです)");
        response = await model.generateContent([
          Content.multi([prompt, DataPart('image/jpeg', imageBytes)])
        ]);
      } else if (text != null) {
        final prompt = TextPart(basePrompt + "\n\nこのテキストを解析してください: 「$text」");
        response = await model.generateContent([Content.text(prompt.text)]);
      } else {
        throw Exception("入力がありません");
      }

      final responseText = response.text;
      if (responseText == null) throw Exception('AIからの応答が空でした');

      final cleanJson = responseText.replaceAll(RegExp(r'```json|```'), '').trim();
      final data = jsonDecode(cleanJson);

      final amount = data['amount'] is int ? data['amount'] : int.tryParse(data['amount'].toString()) ?? 0;
      final debitId = data['debitId'] is int ? data['debitId'] : int.tryParse(data['debitId'].toString()) ?? -1;
      final creditId = data['creditId'] is int ? data['creditId'] : int.tryParse(data['creditId'].toString()) ?? -1;
      final note = data['note'] ?? '';
      DateTime date;
      try {
        date = DateTime.parse(data['date']);
      } catch (_) {
        date = DateTime.now();
      }

      if (!mounted) return;
      _navigateToAddPage(amount, date, note, debitId, creditId, accounts);

    } catch (e) {
      debugPrint('Gemini Error: $e');
      if (mounted) {
        setState(() {
          _status = 'エラーが発生しました:\n$e';
          _isAnalyzing = false;
        });
      }
    }
  }

  // データの保存はAddTransactionPageに任せ、保存成功(true)が返ってきたら閉じる
  Future<void> _navigateToAddPage(int amount, DateTime date, String note, int debitId, int creditId, List<Account> accounts) async {
    setState(() {
      _isAnalyzing = false;
      _status = '解析完了！';
    });

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddTransactionPage(
          accounts: accounts,
          db: widget.db,
          initialData: Transaction(
            id: 0,
            debitAccountId: debitId,
            creditAccountId: creditId,
            amount: amount,
            date: date,
            note: note,
          ),
        ),
      ),
    );

    if (result == true) {
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  // 音声入力開始
  void _startListening() async {
    await _speechToText.listen(onResult: (result) {
      setState(() {
        _lastWords = result.recognizedWords;
      });
    });
    setState(() => _isListening = true);
  }

  // 音声入力停止 -> Geminiへ送信
  void _stopListening() async {
    await _speechToText.stop();
    setState(() => _isListening = false);
    
    if (_lastWords.isNotEmpty) {
      _analyzeWithGemini(text: _lastWords);
    }
  }

  // 画像選択処理
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        imageQuality: 80,
      );
      if (image != null) {
        _analyzeWithGemini(image: image);
      }
    } catch (e) {
      setState(() => _status = '画像選択エラー: $e');
    }
  }

  // テキスト送信処理
  void _submitText() {
    if (_textInputController.text.isEmpty) return;
    FocusScope.of(context).unfocus();
    _analyzeWithGemini(text: _textInputController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AIスマート入力'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.camera_alt), text: '画像'),
            Tab(icon: Icon(Icons.edit_note), text: 'メモ'),
            Tab(icon: Icon(Icons.mic), text: '音声'),
          ],
        ),
      ),
      body: _isAnalyzing
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text(_status, textAlign: TextAlign.center),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                // --- 1. 画像解析タブ ---
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.document_scanner, size: 80, color: Colors.blueGrey),
                      SizedBox(height: 20),
                      Text('レシート または スクショ\nを読み取ります', textAlign: TextAlign.center),
                      SizedBox(height: 40),
                      SizedBox(
                        width: 250,
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: () => _pickImage(ImageSource.camera),
                          icon: Icon(Icons.camera_alt),
                          label: Text('カメラで撮影'),
                        ),
                      ),
                      SizedBox(height: 16),
                      SizedBox(
                        width: 250,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: () => _pickImage(ImageSource.gallery),
                          icon: Icon(Icons.photo_library),
                          label: Text('アルバムから選択'),
                        ),
                      ),
                    ],
                  ),
                ),

                // --- 2. 一行メモタブ ---
                Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_awesome, size: 60, color: Colors.orange),
                      SizedBox(height: 20),
                      Text(
                        '自由にメモを入力してください\n例: 「コンビニ 500円」',
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 30),
                      TextField(
                        controller: _textInputController,
                        decoration: InputDecoration(
                          hintText: 'ここに入力...',
                          border: OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(Icons.send, color: Colors.blue),
                            onPressed: _submitText,
                          ),
                        ),
                        onSubmitted: (_) => _submitText(),
                      ),
                      SizedBox(height: 20),
                      
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: _submitText,
                          icon: Icon(Icons.auto_awesome),
                          label: Text('AIに解析させる'),
                          style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),

                // --- 3. 音声入力タブ ---
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isListening ? Icons.mic : Icons.mic_none, 
                        size: 80, 
                        color: _isListening ? Colors.red : Colors.grey
                      ),
                      SizedBox(height: 20),
                      Text(
                        _isListening ? '聞いています...' : 'マイクボタンを押して\n話しかけてください',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 18),
                      ),
                      SizedBox(height: 20),
                      Text(
                        _lastWords,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 40),
                      GestureDetector(
                        onLongPressStart: (_) => _startListening(),
                        onLongPressEnd: (_) => _stopListening(),
                        child: SizedBox(
                          width: 250,
                          height: 60,
                          child: FilledButton.icon(
                            onPressed: _speechEnabled 
                              ? (_isListening ? _stopListening : _startListening) 
                              : null,
                            icon: Icon(_isListening ? Icons.stop : Icons.mic),
                            label: Text(_isListening ? 'タップして完了' : 'タップして話す'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _isListening ? Colors.red : Colors.blue,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 10),
                      Text('例: 「昨日 コンビニで1200円使った」', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}