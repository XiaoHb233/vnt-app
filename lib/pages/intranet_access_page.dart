import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vnt_app/theme/app_theme.dart';
import 'package:vnt_app/utils/responsive_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 内网访问页面 - 整合美团查询系统
class IntranetAccessPage extends StatefulWidget {
  const IntranetAccessPage({super.key});

  @override
  State<IntranetAccessPage> createState() => _IntranetAccessPageState();
}

class _IntranetAccessPageState extends State<IntranetAccessPage> {
  static const String _serverIpKey = 'intranet_server_ip';
  String _serverIp = '127.0.0.1';
  bool _isLoading = true;
  bool _showWebView = false;
  String _currentUrl = '';
  String _currentTitle = '';
  
  late WebViewController _webViewController;
  final TextEditingController _ipController = TextEditingController();

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
    _webViewController = WebViewController()
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
            setState(() {
              _isLoading = false;
            });
          },
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
    setState(() {
      _showWebView = false;
      _currentUrl = '';
    });
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

    if (_showWebView) {
      return _buildWebViewPage(isDark, primaryColor);
    }

    return Scaffold(
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
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkCardBackground : AppTheme.lightCardBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
          ),
          onPressed: _closeWebView,
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
          WebViewWidget(controller: _webViewController),
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
    return InkWell(
      onTap: () => _openEntry(entry),
      borderRadius: BorderRadius.circular(context.cardRadius),
      child: Container(
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
            Container(
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
    super.dispose();
  }
}
