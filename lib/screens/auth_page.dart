import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import '../main.dart'; 

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final LocalAuthentication auth = LocalAuthentication();
  String _status = '認証してください';

  @override
  void initState() {
    super.initState();
    _authenticate();
  }

  Future<void> _authenticate() async {
    bool authenticated = false;
    setState(() => _status = '認証中...');

    try {
      final bool isDeviceSupported = await auth.isDeviceSupported();
      final bool canCheckBiometrics = await auth.canCheckBiometrics;

      // そもそもロック設定がない端末はそのまま通す
      if (!isDeviceSupported && !canCheckBiometrics) {
        _goToMain();
        return;
      }

      // 認証実行
      authenticated = await auth.authenticate(
        localizedReason: '家計簿のロックを解除',
        options: const AuthenticationOptions(
          stickyAuth: true,
          // ★重要: これを false にすると、生体認証失敗時に「パスコード」入力画面に遷移できます
          // (MainActivityをFlutterFragmentActivityにしたことで正しく動くようになります)
          biometricOnly: false, 
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (e) {
      // 特定のエラー（設定なし等）は許可
      if (e.code == auth_error.notAvailable || 
          e.code == auth_error.notEnrolled || 
          e.code == auth_error.passcodeNotSet) {
        _goToMain();
        return;
      }

      // それ以外のエラー（キャンセルや失敗）は通さない
      if (mounted) {
        setState(() => _status = '認証エラー: ${e.message}');
      }
      return;
    }

    if (!mounted) return;

    if (authenticated) {
      _goToMain();
    } else {
      setState(() => _status = '認証に失敗しました');
    }
  }

  void _goToMain() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const MainScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 80, color: Colors.white),
              const SizedBox(height: 20),
              Text(
                'Dualy Security',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.9)),
              ),
              const SizedBox(height: 10),
              Text(
                _status,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              
              // 再試行ボタン
              OutlinedButton.icon(
                onPressed: _authenticate,
                icon: const Icon(Icons.fingerprint, color: Colors.white),
                label: const Text('ロック解除', style: TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white),
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                ),
              ),
              // ★救済リンクは削除しました
            ],
          ),
        ),
      ),
    );
  }
}