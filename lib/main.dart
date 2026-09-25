import 'package:flutter/material.dart';
import 'screens/self_learning.dart';
import 'screens/login.dart';
import 'session_controller.dart';
import 'screens/report_db.dart';
import 'screens/gemini_chat.dart';
import 'screens/stats.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'theme/lumen_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('Warning: Could not load .env file: $e');
  }
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SRL LoL',
      theme: buildLumenNightTheme(),
      home: const AuthGate(),
    );
  }
}

// 未ログインならログイン画面、ログイン済みならホーム(4タブ)を出す。
// ログアウトするとHomeShellごと破棄されるので、各タブの状態も前のプレイヤーのものは残らない。
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    return session.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const LoginScreen(),
      data: (player) =>
          player == null ? const LoginScreen() : const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  late final List<Widget> _widgetOptions = <Widget>[
    Report_dbWidget(),
    SelflearningWidget(),
    const GeminiChatScreen(),
    const StatsWidget(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _widgetOptions),
      bottomNavigationBar: BottomNavigationBar(
        // 4タブ以上だとshifting型になり非選択ラベルが消えるので固定にする
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.history), label: '振り返り'),
          BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: 'フォーム'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: '壁打ち'),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: '統計'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
