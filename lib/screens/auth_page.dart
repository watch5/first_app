import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import '../main.dart'; // MainScreenを呼ぶためにインポート

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
    _authenticate(); // 画面が開いたらすぐに認証開始
  }

  Future<void> _authenticate() async {
    bool authenticated = false;
    try {
      // 生体認証が使えるか確認
      final bool canAuthenticateWithBiometrics = await auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await auth.isDeviceSupported();

      if (!canAuthenticate) {
        // そもそも指紋なども設定されていない端末なら、そのまま通す（またはエラーにする）
        _goToMain();
        return;
      }

      // 認証実行
      authenticated = await auth.authenticate(
        localizedReason: '家計簿のロックを解除',
        options: const AuthenticationOptions(
          stickyAuth: true, // アプリに戻ってきた時も再認証
          biometricOnly: true,
        ),
      );
    } on PlatformException catch (e) {
      if (e.code == auth_error.notAvailable) {
        // 生体認証が使えない場合
        _goToMain();
        return;
      }
      setState(() => _status = '認証エラー: ${e.message}');
      return;
    }

    if (!mounted) return;

    if (authenticated) {
      _goToMain();
    } else {
      setState(() => _status = '認証できませんでした');
    }
  }

  void _goToMain() {
    // 認証成功！メイン画面へ（戻れないようにpushReplacement）
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const MainScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo,
      body: Center(
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
            ),
            const SizedBox(height: 40),
            // 失敗した時用の再試行ボタン
            OutlinedButton.icon(
              onPressed: _authenticate,
              icon: const Icon(Icons.fingerprint, color: Colors.white),
              label: const Text('ロック解除', style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white),
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}