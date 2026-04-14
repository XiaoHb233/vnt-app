import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vnt_app/theme/app_theme.dart';
import 'package:vnt_app/utils/responsive_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
// 使用 flutter_inappwebview 替代 webview_flutter，性能更好
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// 文件选择器
import 'package:file_picker/file_picker.dart';
// 用于获取 Content URI
import 'package:path_provider/path_provider.dart';

/// 内网访问页面 - 整合美团查询系统
/// 
/// 使用 flutter_inappwebview 优化性能：
/// 1. 硬件加速渲染
/// 2. 更流畅的滚动体验
/// 3. 更好的 JavaScript 性能
class IntranetAccessPage extends StatefulWidget {
  const IntranetAccessPage({super.key});

  @override
  State<IntranetAccessPage> createState() => IntranetAccessPageState();
}

// 暴露 State 类以便外部访问
class IntranetAccessPageState extends State<IntranetAccessPage> {
  static const String _serverIpKey = 'intranet_server_ip';
  String _serverIp = '127.0.0.1';
  bool _showWebView = false;
  String _currentUrl = '';
  String _currentTitle = '';
  
  // InAppWebView 控制器
  InAppWebViewController? _webViewController;
  final TextEditingController _ipController = TextEditingController();

  // 使用 ValueNotifier 替代 setState，减少 WebView 页面重建
  final ValueNotifier<bool> _loadingNotifier = ValueNotifier<bool>(true);

  // 入口配置
  final List<Map<String, dynamic>> _entries = const [
    {
      'id': 'user',
      'name': '用户端',
      'desc': '查询服务',
      'icon': Icons.person_outline,
      'path': '/index.html',
    },
    {
      'id': 'admin',
      'name': '管理员',
      'desc': '后台管理',
      'icon': Icons.admin_panel_settings_outlined,
      'path': '/admin/dashboard.html',
    },
    {
      'id': 'asyn',
      'name': '异步定时',
      'desc': '定时任务',
      'icon': Icons.timer_outlined,
      'path': '/admin/asyn_post.html',
    },
    {
      'id': 'ql',
      'name': 'QL定时',
      'desc': '青龙面板',
      'icon': Icons.schedule_outlined,
      'path': '/admin/ql_scheduler.html',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadServerIp();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _loadingNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadServerIp() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serverIp = prefs.getString(_serverIpKey) ?? '127.0.0.1';
    });
  }

  Future<void> _saveServerIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverIpKey, ip);
    setState(() {
      _serverIp = ip;
    });
  }

  // 上次返回时间（用于双重返回逻辑）
  int? _lastBackTime;
  static const int _backInterval = 1500; // 1.5秒内双击返回

  // 处理返回按钮点击 - 与 HBuilder_app 一致：直接返回入口页面
  void _handleBackButton() {
    _closeWebView();
  }

  // 处理物理返回键 - 与 HBuilder_app 一致的双重返回逻辑
  Future<bool> _handlePhysicalBackButton() async {
    if (_webViewController != null) {
      // 先尝试 WebView 返回
      final canGoBack = await _webViewController!.canGoBack();
      if (canGoBack) {
        await _webViewController!.goBack();
        return false; // 不退出
      }
    }
    
    // WebView 无法返回，使用双重返回逻辑
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastBackTime == null || now - _lastBackTime! > _backInterval) {
      _lastBackTime = now;
      // 显示提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('再按一次返回键退出'),
            duration: Duration(milliseconds: 1500),
          ),
        );
      }
      return false; // 不退出
    }
    
    // 第二次按返回键（1.5秒内）：关闭 WebView 回到入口页面
    _closeWebView();
    return false; // 不退出页面，只是关闭 WebView
  }

  void _closeWebView() {
    setState(() {
      _showWebView = false;
      _currentUrl = '';
      _currentTitle = '';
    });
    _webViewController = null;
  }

  void _openEntry(String path, String title) {
    final url = 'http://$_serverIp:8080$path';
    setState(() {
      _currentUrl = url;
      _currentTitle = title;
      _showWebView = true;
    });
  }

  void _refreshPage() {
    _webViewController?.reload();
  }

  // 重置到入口页面（供外部调用）
  void resetToEntryPage() {
    _closeWebView();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (Widget child, Animation<double> animation) {
        final bool isWebView = child is WillPopScope;

        final offsetAnimation = Tween<Offset>(
          begin: isWebView ? const Offset(1.0, 0.0) : const Offset(-1.0, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOut,
        ));

        return SlideTransition(
          position: offsetAnimation,
          child: child,
        );
      },
      child: _showWebView
          ? _buildWebViewPage(isDark, primaryColor)
          : _buildMainPage(isDark, primaryColor),
    );
  }

  Widget _buildMainPage(bool isDark, Color primaryColor) {
    return Scaffold(
      key: const ValueKey('mainPage'),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkCardBackground : AppTheme.lightCardBackground,
        elevation: 0,
        title: Text(
          '内网访问',
          style: TextStyle(
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
            fontSize: context.fontMedium,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: ResponsiveUtils.padding(context, all: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isDark, primaryColor),
            SizedBox(height: context.spacingLarge),
            _buildServerConfig(isDark, primaryColor),
            SizedBox(height: context.spacingLarge),
            _buildEntriesGrid(isDark, primaryColor),
            SizedBox(height: context.spacingLarge),
            _buildTipsCard(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildWebViewPage(bool isDark, Color primaryColor) {
    return WillPopScope(
      key: const ValueKey('webViewPage'),
      onWillPop: _handlePhysicalBackButton,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
        appBar: AppBar(
          backgroundColor: isDark ? AppTheme.darkCardBackground : AppTheme.lightCardBackground,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back,
              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
            ),
            onPressed: _handleBackButton,
          ),
          title: Text(
            _currentTitle,
            style: TextStyle(
              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
              fontSize: context.fontMedium,
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(
                Icons.refresh,
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
              ),
              onPressed: _refreshPage,
            ),
          ],
        ),
        body: Stack(
          children: [
            // InAppWebView - 性能更好的 WebView
            InAppWebView(
              initialUrlRequest: URLRequest(url: Uri.parse(_currentUrl)),
              initialOptions: InAppWebViewGroupOptions(
                crossPlatform: InAppWebViewOptions(
                  // JavaScript 支持
                  javaScriptEnabled: true,
                  // 透明背景
                  transparentBackground: true,
                  // 用户代理
                  userAgent: 'Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                ),
                android: AndroidInAppWebViewOptions(
                  // 允许混合内容（HTTP/HTTPS）
                  mixedContentMode: AndroidMixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
                  // 媒体播放不需要用户手势
                  mediaPlaybackRequiresUserGesture: false,
                  // 数据库支持
                  databaseEnabled: true,
                  // DOM 存储支持
                  domStorageEnabled: true,
                  // 支持缩放
                  supportZoom: true,
                  // 显示缩放控件
                  builtInZoomControls: true,
                  // 硬件加速
                  hardwareAcceleration: true,
                ),
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              onLoadStart: (controller, url) {
                _loadingNotifier.value = true;
              },
              onLoadStop: (controller, url) {
                _loadingNotifier.value = false;
              },
              onLoadError: (controller, url, code, message) {
                debugPrint('WebView 错误: $code - $message');
                _loadingNotifier.value = false;
              },
              onProgressChanged: (controller, progress) {
                if (progress == 100) {
                  _loadingNotifier.value = false;
                }
              },
            ),
            // 加载指示器
            ValueListenableBuilder<bool>(
              valueListenable: _loadingNotifier,
              builder: (context, isLoading, child) {
                return isLoading
                    ? Container(
                        color: isDark
                            ? AppTheme.darkBackground
                            : AppTheme.lightBackground,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                color: primaryColor,
                              ),
                              SizedBox(height: context.spacingMedium),
                              Text(
                                '正在连接服务器...',
                                style: TextStyle(
                                  color: isDark
                                      ? AppTheme.darkTextSecondary
                                      : AppTheme.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, Color primaryColor) {
    return Row(
      children: [
        Container(
          width: context.iconXLarge,
          height: context.iconXLarge,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryColor, primaryColor.withOpacity(0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(context.cardRadius),
          ),
          child: Icon(
            Icons.language,
            color: Colors.white,
            size: context.iconLarge,
          ),
        ),
        SizedBox(width: context.spacingMedium),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '内网服务',
                style: TextStyle(
                  fontSize: context.fontLarge,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
              ),
              Text(
                '访问本地服务器功能',
                style: TextStyle(
                  fontSize: context.fontSmall,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildServerConfig(bool isDark, Color primaryColor) {
    return Container(
      padding: ResponsiveUtils.padding(context, all: 20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardBackground : AppTheme.lightCardBackground,
        borderRadius: BorderRadius.circular(context.cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.settings,
                size: context.iconMedium,
                color: primaryColor,
              ),
              SizedBox(width: context.spacingSmall),
              Text(
                '服务器配置',
                style: TextStyle(
                  fontSize: context.fontMedium,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: context.spacingMedium),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ipController..text = _serverIp,
                  style: TextStyle(
                    fontSize: context.fontMedium,
                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: '服务器 IP',
                    hintText: '例如: 192.168.1.100',
                    labelStyle: TextStyle(
                      fontSize: context.fontSmall,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    ),
                    hintStyle: TextStyle(
                      fontSize: context.fontSmall,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    ),
                    prefixIcon: Icon(
                      Icons.computer,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(context.cardRadius),
                      borderSide: BorderSide(
                        color: isDark ? Colors.white24 : Colors.black12,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(context.cardRadius),
                      borderSide: BorderSide(
                        color: isDark ? Colors.white24 : Colors.black12,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(context.cardRadius),
                      borderSide: BorderSide(color: primaryColor),
                    ),
                    filled: true,
                    fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    _serverIp = value;
                  },
                ),
              ),
              SizedBox(width: context.spacingMedium),
              ElevatedButton(
                onPressed: () {
                  _saveServerIp(_ipController.text);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('服务器地址已保存: ${_ipController.text}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: ResponsiveUtils.padding(context, horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(context.cardRadius),
                  ),
                ),
                child: Text(
                  '保存',
                  style: TextStyle(fontSize: context.fontMedium),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEntriesGrid(bool isDark, Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '功能入口',
          style: TextStyle(
            fontSize: context.fontMedium,
            fontWeight: FontWeight.w600,
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
          ),
        ),
        SizedBox(height: context.spacingMedium),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: ResponsiveUtils.isTablet(context) ? 3 : 2,
            crossAxisSpacing: context.spacingMedium,
            mainAxisSpacing: context.spacingMedium,
            childAspectRatio: 1.3,
          ),
          itemCount: _entries.length,
          itemBuilder: (context, index) {
            final entry = _entries[index];
            return _buildEntryCard(
              entry['id'] as String,
              entry['name'] as String,
              entry['desc'] as String,
              entry['icon'] as IconData,
              entry['path'] as String,
              isDark,
              primaryColor,
            );
          },
        ),
      ],
    );
  }

  Widget _buildEntryCard(
    String id,
    String name,
    String desc,
    IconData icon,
    String path,
    bool isDark,
    Color primaryColor,
  ) {
    return GestureDetector(
      onTap: () => _openEntry(path, name),
      child: Container(
        padding: ResponsiveUtils.padding(context, all: 16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCardBackground : AppTheme.lightCardBackground,
          borderRadius: BorderRadius.circular(context.cardRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: context.iconXLarge,
              height: context.iconXLarge,
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(context.cardRadius),
              ),
              child: Icon(
                icon,
                color: primaryColor,
                size: context.iconLarge,
              ),
            ),
            SizedBox(height: context.spacingSmall),
            Text(
              name,
              style: TextStyle(
                fontSize: context.fontMedium,
                fontWeight: FontWeight.w600,
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
              ),
            ),
            Text(
              desc,
              style: TextStyle(
                fontSize: context.fontSmall,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipsCard(bool isDark) {
    return Container(
      padding: ResponsiveUtils.padding(context, all: 16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(context.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: context.iconSmall,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              ),
              SizedBox(width: context.spacingSmall),
              Text(
                '使用说明',
                style: TextStyle(
                  fontSize: context.fontMedium,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: context.spacingSmall),
          Text(
            '• 用户端：普通查询服务\n• 管理员：后台管理功能\n• 异步定时：定时任务管理\n• QL定时：青龙面板管理',
            style: TextStyle(
              fontSize: context.fontSmall,
              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
