import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vnt_app/theme/app_theme.dart';
import 'package:vnt_app/utils/responsive_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
// 导入平台特定的 WebView 设置
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
// 文件选择器
import 'package:file_picker/file_picker.dart';

/// 内网访问页面 - 整合美团查询系统
class IntranetAccessPage extends StatefulWidget {
  const IntranetAccessPage({super.key});

  @override
  State<IntranetAccessPage> createState() => IntranetAccessPageState();
}

// 暴露 State 类以便外部访问
class IntranetAccessPageState extends State<IntranetAccessPage> {
  static const String _serverIpKey = 'intranet_server_ip';
  String _serverIp = '127.0.0.1';
  bool _isLoading = true;
  bool _showWebView = false;
  String _currentUrl = '';
  String _currentTitle = '';
  
  late WebViewController _webViewController;
  final TextEditingController _ipController = TextEditingController();
  // 缓存 WebViewWidget，避免重复创建
  Widget? _cachedWebViewWidget;

  // 入口配置
  final List<Map<String, dynamic>> _entries = [
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
    _initWebView();
    _loadServerIp();
  }

  void _initWebView() {
    // 创建平台特定的参数
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _webViewController = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView 错误: ${error.errorCode} - ${error.description}');
            setState(() {
              _isLoading = false;
            });
          },
        ),
      )
      ..setUserAgent('Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36');

    // Android 特定设置：确保使用应用的网络栈（包括 VPN）
    if (_webViewController.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      final androidController = _webViewController.platform as AndroidWebViewController;

      // 禁用媒体播放需要用户手势
      androidController.setMediaPlaybackRequiresUserGesture(false);

      // 配置文件上传支持
      androidController.setOnShowFileSelector((FileSelectorParams params) async {
        try {
          // 根据 acceptTypes 决定文件类型
          FileType fileType = FileType.any;
          List<String>? allowedExtensions;
          final acceptTypes = params.acceptTypes;
          
          if (acceptTypes.isNotEmpty) {
            // 检查是否是图片
            if (acceptTypes.any((type) => 
                type.contains('image') || type.contains('jpg') || type.contains('png'))) {
              fileType = FileType.image;
            } 
            // 检查是否是 Python 文件
            else if (acceptTypes.any((type) => 
                type.contains('python') || type.contains('.py'))) {
              fileType = FileType.custom;
              allowedExtensions = ['py'];
            }
          }
          
          // 使用 FilePicker 选择文件
          final result = await FilePicker.platform.pickFiles(
            type: fileType,
            allowedExtensions: allowedExtensions,
            allowMultiple: params.mode == FileSelectorMode.openMultiple,
            // 关键：使用 withData: true 获取文件内容
            withData: false,
            withReadStream: false,
          );
          
          // 返回 Content URI 列表
          if (result != null && result.files.isNotEmpty) {
            final List<String> uris = [];
            for (final file in result.files) {
              if (file.path != null) {
                // 将本地路径转换为 Content URI
                final contentUri = await _getContentUri(file.path!, file.name);
                if (contentUri != null) {
                  uris.add(contentUri);
                }
              }
            }
            return uris;
          }
          return [];
        } catch (e) {
          debugPrint('文件选择错误: $e');
          return [];
        }
      });
    }
  }

  /// 将本地文件路径转换为 Content URI
  /// 这是 Android WebView 文件上传必需的格式
  Future<String?> _getContentUri(String filePath, String fileName) async {
    try {
      // 使用 MethodChannel 调用原生代码获取 Content URI
      const platform = MethodChannel('top.wherewego.vnt/filepicker');
      final String? contentUri = await platform.invokeMethod('getContentUri', {
        'filePath': filePath,
        'fileName': fileName,
      });
      return contentUri;
    } catch (e) {
      debugPrint('获取 Content URI 失败: $e');
      // 如果原生方法失败，尝试使用 file:// 协议作为后备
      // 注意：这可能不适用于所有 Android 版本
      return 'file://$filePath';
    }
  }

  // 上次返回时间（用于双重返回逻辑）
  int? _lastBackTime;
  static const int _backInterval = 1500; // 1.5秒内双击返回

  // 处理返回按钮点击 - 与 HBuilder_app 一致：直接返回入口页面
  void _handleBackButton() {
    _closeWebView();
  }

  // 处理物理返回键 - 与 HBuilder_app 一致：双重返回逻辑
  Future<bool> _handlePhysicalBackButton() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final adminUrl = 'http://$_serverIp/admin/dashboard.html';

    // 第一次按返回键（1.5秒内）
    if (_lastBackTime == null || now - _lastBackTime! > _backInterval) {
      _lastBackTime = now;

      try {
        // 获取当前 URL
        final currentUrl = await _webViewController.currentUrl() ?? '';

        // 检查当前是否在 AsynPost 或 QL 页面
        if (currentUrl.contains('/asyn_post.html') ||
            currentUrl.contains('/ql_scheduler.html')) {
          // 直接跳转到后台首页
          await _webViewController.loadRequest(Uri.parse(adminUrl));
          _showToast('已返回后台');
        } else {
          // 尝试历史记录返回
          if (await _webViewController.canGoBack()) {
            await _webViewController.goBack();
            _showToast('再按一次返回首页');
          } else {
            // 没有历史记录，关闭 WebView 回到入口页面
            _closeWebView();
            return false; // 返回 false 阻止页面退出，只是切换显示状态
          }
        }
      } catch (e) {
        // 出错时直接跳转到后台首页
        await _webViewController.loadRequest(Uri.parse(adminUrl));
        _showToast('已返回后台');
      }

      return false; // 不退出页面
    } else {
      // 第二次按返回键（1.5秒内）：关闭 WebView 回到入口页面
      _lastBackTime = null;
      _closeWebView();
      return false; // 返回 false 阻止页面退出，只是切换显示状态
    }
  }

  // 显示提示（类似 HBuilder_app 的 showGestureHint）
  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.black87,
      ),
    );
  }

  Future<void> _loadServerIp() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serverIp = prefs.getString(_serverIpKey) ?? '127.0.0.1';
      _isLoading = false;
    });
  }

  Future<void> _saveServerIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverIpKey, ip);
    setState(() {
      _serverIp = ip;
    });
  }

  String _buildUrl(String path) {
    return 'http://$_serverIp$path';
  }

  void _openEntry(Map<String, dynamic> entry) {
    final url = _buildUrl(entry['path']);
    setState(() {
      _currentUrl = url;
      _currentTitle = entry['name'];
      _showWebView = true;
    });
    _webViewController.loadRequest(Uri.parse(url));
  }

  void _closeWebView() {
    _lastBackTime = null; // 重置返回时间
    setState(() {
      _showWebView = false;
      _currentUrl = '';
    });
  }

  /// 重置页面状态 - 当点击底部导航栏内网按钮时调用
  void resetToEntryPage() {
    if (_showWebView) {
      _closeWebView();
    }
  }

  void _refreshPage() {
    _webViewController.reload();
  }

  void _showConfigDialog() {
    _ipController.text = _serverIp;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppTheme.darkCardBackground
            : AppTheme.lightCardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.cardRadius),
        ),
        title: Text(
          '服务器配置',
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? AppTheme.darkTextPrimary
                : AppTheme.lightTextPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(context.spacingSmall),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(context.cardRadius),
              ),
              child: Row(
                children: [
                  Text(
                    '当前: ',
                    style: TextStyle(
                      fontSize: context.fontSmall,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _serverIp,
                      style: TextStyle(
                        fontSize: context.fontSmall,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.lightTextPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: context.spacingMedium),
            TextField(
              controller: _ipController,
              decoration: InputDecoration(
                labelText: '服务器地址',
                hintText: '例如: 127.0.0.1 或 192.168.1.100',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(context.cardRadius),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(context.cardRadius),
                  borderSide: BorderSide(
                    color: Theme.of(context).primaryColor,
                    width: 2,
                  ),
                ),
              ),
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppTheme.darkTextPrimary
                    : AppTheme.lightTextPrimary,
              ),
            ),
            SizedBox(height: context.spacingSmall),
            Text(
              '请输入IP地址或域名，不需要添加 http:// 前缀',
              style: TextStyle(
                fontSize: context.fontSmall,
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              String ip = _ipController.text.trim();
              
              // 移除可能存在的 http:// 或 https:// 前缀
              ip = ip.replaceAll(RegExp(r'^https?://'), '');
              
              // 移除可能存在的路径部分
              ip = ip.split('/')[0];
              
              if (ip.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入服务器地址')),
                );
                return;
              }
              
              await _saveServerIp(ip);
              Navigator.pop(context);
              
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('服务器配置已保存')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(context.buttonRadius),
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> animation) {
        // 根据 _showWebView 状态判断动画方向，而不是依赖 child.key
        final offsetAnimation = Tween<Offset>(
          begin: _showWebView ? const Offset(1.0, 0.0) : const Offset(-1.0, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOutCubic,
        ));
        return SlideTransition(
          position: offsetAnimation,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      child: _showWebView
          ? _buildWebViewPage(isDark, primaryColor)
          : _buildMainPage(isDark, primaryColor),
      // 使用 Stack 布局确保动画过程中两个页面都能正确显示
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
    );
  }

  /// 构建 WebViewWidget，Android 平台使用 Hybrid Composition 模式优化键盘体验
  Widget _buildWebViewWidget() {
    // 使用缓存的 WebViewWidget，避免重复创建
    if (_cachedWebViewWidget != null) {
      return _cachedWebViewWidget!;
    }

    // Android 平台使用 Hybrid Composition 模式，解决软键盘弹出时的掉帧问题
    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      _cachedWebViewWidget = WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams(
          controller: _webViewController.platform,
          // 关键：启用 Hybrid Composition 模式，提供更好的键盘支持
          displayWithHybridComposition: true,
        ),
      );
    } else {
      // iOS 平台使用默认实现
      _cachedWebViewWidget = WebViewWidget(controller: _webViewController);
    }
    return _cachedWebViewWidget!;
  }

  Widget _buildMainPage(bool isDark, Color primaryColor) {
    return Scaffold(
      key: const ValueKey('mainPage'),
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(context.spacingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 页面头部
              _buildHeader(isDark, primaryColor),
              SizedBox(height: context.spacingLarge),

              // 服务器信息卡片
              _buildServerInfoCard(isDark, primaryColor),
              SizedBox(height: context.spacingLarge),

              // 入口选择
              _buildSectionTitle(isDark, '访问入口'),
              SizedBox(height: context.spacingSmall),
              _buildEntryGrid(isDark, primaryColor),
              SizedBox(height: context.spacingLarge),

              // 说明
              _buildTipsCard(isDark),
            ],
          ),
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
            _buildWebViewWidget(),
            if (_isLoading)
              Container(
                color: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
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
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
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
                '内网访问',
                style: TextStyle(
                  fontSize: context.fontXLarge,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
              ),
              Text(
                '访问内网服务',
                style: TextStyle(
                  fontSize: context.fontBody,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildServerInfoCard(bool isDark, Color primaryColor) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardBackground : AppTheme.lightCardBackground,
        borderRadius: BorderRadius.circular(context.cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: ResponsiveUtils.padding(context, all: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: context.listItemIconContainerSize,
                  height: context.listItemIconContainerSize,
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(context.cardRadius),
                  ),
                  child: Icon(
                    Icons.dns_outlined,
                    color: primaryColor,
                    size: context.iconSmall,
                  ),
                ),
                SizedBox(width: context.spacingMedium),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '服务器地址',
                        style: TextStyle(
                          fontSize: context.fontMedium,
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                        ),
                      ),
                      Text(
                        _serverIp,
                        style: TextStyle(
                          fontSize: context.fontBody,
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.edit,
                    color: primaryColor,
                    size: context.iconSmall,
                  ),
                  onPressed: _showConfigDialog,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(bool isDark, String title) {
    final primaryColor = Theme.of(context).primaryColor;
    return Padding(
      padding: EdgeInsets.only(left: context.spacingXSmall / 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: context.fontBody,
          fontWeight: FontWeight.w600,
          color: primaryColor,
        ),
      ),
    );
  }

  Widget _buildEntryGrid(bool isDark, Color primaryColor) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: context.spacingSmall,
        mainAxisSpacing: context.spacingSmall,
        childAspectRatio: 1.2,
      ),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return _buildEntryCard(entry, isDark, primaryColor);
      },
    );
  }

  Widget _buildEntryCard(Map<String, dynamic> entry, bool isDark, Color primaryColor) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + (_entries.indexOf(entry) * 100)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, (1 - value) * 20),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openEntry(entry),
          borderRadius: BorderRadius.circular(context.cardRadius),
          splashColor: primaryColor.withOpacity(0.1),
          highlightColor: primaryColor.withOpacity(0.05),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCardBackground : AppTheme.lightCardBackground,
              borderRadius: BorderRadius.circular(context.cardRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Hero(
                  tag: 'entry_icon_${entry['id']}',
                  child: Container(
                    width: context.iconXLarge,
                    height: context.iconXLarge,
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(context.cardRadius),
                    ),
                    child: Icon(
                      entry['icon'] as IconData,
                      color: primaryColor,
                      size: context.iconLarge,
                    ),
                  ),
                ),
                SizedBox(height: context.spacingSmall),
                Text(
                  entry['name'] as String,
                  style: TextStyle(
                    fontSize: context.fontMedium,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                  ),
                ),
                SizedBox(height: context.spacingXSmall / 2),
                Text(
                  entry['desc'] as String,
                  style: TextStyle(
                    fontSize: context.fontSmall,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
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

  @override
  void dispose() {
    _ipController.dispose();
    // 释放 WebViewController 资源
    _webViewController.dispose();
    super.dispose();
  }
}
