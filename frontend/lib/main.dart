import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'screens/login_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'screens/dashboard_screen.dart';
import 'screens/capture_screen.dart';
import 'services/api_service.dart';

List<CameraDescription> cameras = [];
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 不再在 main() 中全局初始化摄像头，避免一进 App（包括登录页）就申请浏览器权限
  runApp(const MistakeMentorApp());
}


class MistakeMentorApp extends StatelessWidget {
  const MistakeMentorApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'MistakeMentor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      home: const RootScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({Key? key}) : super(key: key);

  @override
  _RootScreenState createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    const storage = FlutterSecureStorage();
    String? token = await storage.read(key: 'jwt_token');
    // TODO: 生产环境可在此处调用 /api/v1/users/me 校验 token 是否过期
    setState(() {
      _isAuthenticated = token != null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.indigo)),
      );
    }
    return _isAuthenticated ? const MainNavigationShell() : const LoginScreen();
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({Key? key}) : super(key: key);

  @override
  _MainNavigationShellState createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;
  final ValueNotifier<bool> _refreshNotifier = ValueNotifier(false); // 新增：刷新信号源

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      DashboardScreen(refreshNotifier: _refreshNotifier), // 注入信号
      const Center(child: Text('敬请期待复习模式')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.indigo,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: '面板'),
          BottomNavigationBarItem(icon: Icon(Icons.history_edu), label: '复习'),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          if (cameras.isEmpty) {
            try {
              cameras = await availableCameras();
            } catch (e) {
              print('Error initializing cameras: $e');
            }
          }

          if (cameras.isNotEmpty) {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CaptureScreen(),
              ),
            );
            // 如果成功上传，自动刷新
            if (result == true) {
               _refreshNotifier.value = !_refreshNotifier.value;
            }
          } else {
             if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未检测到可用摄像头！')));
             }
          }
        },

        backgroundColor: Colors.indigo,
        child: const Icon(Icons.camera_alt, color: Colors.white, size: 28),
      ),
    );
  }
}
