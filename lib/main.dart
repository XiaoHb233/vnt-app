import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vnt_app/src/rust/frb_generated.dart';
import 'package:vnt_app/src/rust/api/vnt_api.dart';
import 'package:vnt_app/theme/app_theme.dart';
import 'package:vnt_app/theme/theme_provider.dart';
import 'package:vnt_app/pages/main_navigation_shell.dart';
import 'package:vnt_app/data_persistence.dart';
import 'package:vnt_app/vnt/vnt_manager.dart';
import 'package:vnt_app/utils/responsive_utils.dart';
import 'package:vnt_app/utils/log_utils.dart';
import 'package:vnt_app/network_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await copyLogConfig();
  } catch (e) {
    debugPrint('copyLogConfig catch $e');
  }

  await RustLib.init();

  // 初始化日志系统
  try {
    final logDir = await LogUtils.getLogDirectory();
    debugPrint('日志目录: $logDir');

    final logsDirectory = Directory(logDir);
    if (!await logsDirectory.exists()) {
      await logsDirectory.create(recursive: true);
      debugPrint('创建日志目录: $logDir');
    }

    initLogWithPath(logDir: logDir);
    debugPrint('日志系统初始化成功，日志目录: $logDir');
  } catch (e) {
    debugPrint('初始化日志系统失败: $e');
  }

  if (Platform.isAndroid) {
    VntAppCall.init();
  }

  runApp(const VntApp());
}

class VntApp extends StatefulWidget {
  const VntApp({super.key});

  @override
  State<VntApp> createState() => _VntAppState();
}

class _VntAppState extends State<VntApp> {
  ThemeMode _themeMode = ThemeMode.system;
  Color _customThemeColor = AppTheme.primaryColor;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
    _loadCustomThemeColor();
  }

  Future<void> _loadThemeMode() async {
    final savedMode = await DataPersistence().loadThemeMode();
    if (savedMode != null && mounted) {
      setState(() {
        _themeMode = savedMode;
      });
    }
  }

  Future<void> _loadCustomThemeColor() async {
    final savedColor = await DataPersistence().loadCustomThemeColor();
    if (savedColor != null && mounted) {
      setState(() {
        _customThemeColor = savedColor;
      });
    }
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
    DataPersistence().saveThemeMode(mode);
  }

  void _setCustomThemeColor(Color color) {
    setState(() {
      _customThemeColor = color;
    });
    DataPersistence().saveCustomThemeColor(color);
  }

  @override
  Widget build(BuildContext context) {
    return ThemeProvider(
      themeMode: _themeMode,
      setThemeMode: _setThemeMode,
      customThemeColor: _customThemeColor,
      setCustomThemeColor: _setCustomThemeColor,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'VNT App',
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('zh', 'Hans'),
          Locale('en', ''),
        ],
        locale: const Locale('zh', 'CN'),
        // 优化性能：使用简单页面切换动画，减少键盘弹出时的掉帧
        theme: AppTheme.createLightTheme(_customThemeColor).copyWith(
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: <TargetPlatform, PageTransitionsBuilder>{
              TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            },
          ),
        ),
        darkTheme: AppTheme.createDarkTheme(_customThemeColor).copyWith(
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: <TargetPlatform, PageTransitionsBuilder>{
              TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            },
          ),
        ),
        themeMode: _themeMode,
        home: PopScope(
          canPop: false,
          onPopInvoked: (didPop) {
            if (didPop) return;
            if (Platform.isAndroid) {
              VntAppCall.moveTaskToBack();
            }
          },
          child: const MainApp(),
        ),
      ),
    );
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  @override
  void initState() {
    super.initState();

    // 设置Android启动回调
    VntAppCall.setStartCall((String? configKey) async {
      try {
        final dataPersistence = DataPersistence();

        String? targetKey = configKey;
        if (targetKey == null || targetKey.isEmpty) {
          targetKey = await VntAppCall.getTileConfigKey();
          debugPrint('从磁贴获取配置key: $targetKey');
        }

        if (targetKey == null || targetKey.isEmpty) {
          targetKey = await dataPersistence.loadDefaultKey();
          if (targetKey == null || targetKey.isEmpty) {
            debugPrint('磁贴启动：未设置默认配置');
            return;
          }
        }

        final configs = await dataPersistence.loadData();
        final config = configs.where((c) => c.itemKey == targetKey).firstOrNull;

        if (config == null) {
          debugPrint('磁贴启动：配置不存在 (key: $targetKey)');
          return;
        }

        if (vntManager.hasConnection()) {
          debugPrint('磁贴启动：检测到已有连接，先断开所有连接');
          await vntManager.removeAll();
          await Future.delayed(const Duration(milliseconds: 1000));
          debugPrint('磁贴启动：断开完成，准备连接新配置');
        }

        if (vntManager.isConnecting()) {
          debugPrint('磁贴启动：正在连接中，跳过');
          return;
        }

        debugPrint('磁贴启动：开始连接配置 [${config.configName}] (key: ${config.itemKey})');
        final receivePort = ReceivePort();

        receivePort.listen((msg) {
          if (msg is String) {
            if (msg == 'success') {
              debugPrint('磁贴启动：连接成功');
              VntAppCall.updateWidgetAndTile(true);
            } else if (msg == 'stop') {
              vntManager.remove(config.itemKey);
              debugPrint('磁贴启动：连接失败或停止');
              VntAppCall.updateWidgetAndTile(vntManager.hasConnection());
            }
          } else if (msg is RustErrorInfo) {
            vntManager.remove(config.itemKey);
            debugPrint('磁贴启动：连接错误 - ${msg.msg}');
            VntAppCall.updateWidgetAndTile(vntManager.hasConnection());
          }
        });

        await vntManager.create(config, receivePort.sendPort);
        debugPrint('磁贴启动：VntBox创建完成，等待连接结果');
      } catch (e) {
        debugPrint('磁贴启动连接失败: $e');
        VntAppCall.updateWidgetAndTile(vntManager.hasConnection());
      }
    });
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MainNavigationShell(onThemeChanged: _onThemeChanged);
  }
}

Future<void> copyLogConfig() async {
  if (!Platform.isAndroid) {
    return;
  }
  final directory = await getApplicationDocumentsDirectory();
  final logConfigFile = File('${directory.path}/logs/log4rs.yaml');
  if (!logConfigFile.parent.existsSync()) {
    await logConfigFile.parent.create(recursive: true);
  }

  if (await logConfigFile.exists()) {
    debugPrint('日志配置已存在');
    return;
  }

  final byteData = await rootBundle.load('assets/log4rs.yaml');
  await logConfigFile.writeAsBytes(byteData.buffer
      .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
}
