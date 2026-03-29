import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'screens/login_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'screens/dashboard_screen.dart';
import 'screens/capture_screen.dart';
import 'screens/review_session_screen.dart';
import 'screens/statistics_screen.dart';
import 'services/api_service.dart';

import 'theme.dart'; // 引入主题
import 'package:image_picker/image_picker.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 全局主题切换信号
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MistakeMentorApp());
}

class MistakeMentorApp extends StatelessWidget {
  const MistakeMentorApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'MistakeMentor',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightEyeCare(), // 使用护眼亮色
          darkTheme: AppTheme.darkEyeCare(), // 使用护眼暗色
          themeMode: themeMode,
          home: const RootScreen(),
        );
      },
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
        body: Center(child: CircularProgressIndicator()),
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
      DashboardScreen(refreshNotifier: _refreshNotifier), // 实际上是首页错题列表
      ReviewSessionScreen(refreshNotifier: _refreshNotifier),
      StatisticsScreen(refreshNotifier: _refreshNotifier),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
          BottomNavigationBarItem(icon: Icon(Icons.history_edu), label: '复习'),
          BottomNavigationBarItem(icon: Icon(Icons.insights), label: '看板'),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showUploadModal(context);
        },
        child: const Icon(Icons.add, size: 28),
      ),
    );
  }

  void _showUploadModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.blue),
                title: const Text('拍照上传'),
                onTap: () async {
                  Navigator.pop(sheetContext); // Close the modal
                  
                  List<CameraDescription> available = [];
                  try {
                    available = await availableCameras();
                  } catch (e) {
                    print('Error initializing cameras: $e');
                  }
                  
                  if (available.isNotEmpty) {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CaptureScreen(cameras: available),
                      ),
                    );
                    if (result == true) {
                       _refreshNotifier.value = !_refreshNotifier.value;
                    }
                  } else {
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未检测到可用摄像头！')));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.green),
                title: const Text('从相册选择'),
                onTap: () async {
                  Navigator.pop(sheetContext); // Close the modal
                  
                  final ImagePicker picker = ImagePicker();
                  final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                  
                  if (image != null) {
                    final bytes = await image.readAsBytes();
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CaptureScreen(
                          cameras: const [], // Empty means local image mode
                          initialImageBytes: bytes,
                          initialImageName: image.name,
                        ),
                      ),
                    );
                    if (result == true) {
                       _refreshNotifier.value = !_refreshNotifier.value;
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
