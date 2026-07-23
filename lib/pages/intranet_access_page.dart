import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vnt_app/theme/app_theme.dart';
import 'package:vnt_app/utils/responsive_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 内网访问页面 - 使用原生 WebView Activity 获得最佳键盘体验
class IntranetAccessPage extends StatefulWidget {
  const IntranetAccessPage({super.key});

  @override
  State<IntranetAccessPage> createState() => IntranetAccessPageState();
}

class IntranetAccessPageState extends State<IntranetAccessPage> {
  static const String _serverIpKey = 'intranet_server_ip';
  static const String _userPathKey = 'intranet_user_path';
  static const String _adminPathKey = 'intranet_admin_path';
  static const String _asynPathKey = 'intranet_asyn_path';
  static const String _qlPathKey = 'intranet_ql_path';
  static const MethodChannel _channel = MethodChannel('top.wherewego.vnt/webview');

  String _serverIp = '127.0.0.1';
  final Map<String, String> _entryPaths = {
    'user': '/',
    'admin': '/admin',
    'asyn': '/admin/asyn_post.html',
    'ql': '/admin/ql_scheduler.html',
  };
  final _ipController = TextEditingController();
  final Map<String, TextEditingController> _pathControllers = {};

  final _entries = const [
    {'id': 'user', 'name': '用户端', 'desc': '查询服务', 'icon': Icons.person_outline},
    {'id': 'admin', 'name': '管理员', 'desc': '后台管理', 'icon': Icons.admin_panel_settings_outlined},
    {'id': 'asyn', 'name': '异步定时', 'desc': '定时任务', 'icon': Icons.timer_outlined},
    {'id': 'ql', 'name': 'QL定时', 'desc': '青龙面板', 'icon': Icons.schedule_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _loadServerIp();
  }

  Future<void> _loadServerIp() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serverIp = prefs.getString(_serverIpKey) ?? '127.0.0.1';
      _entryPaths['user'] = prefs.getString(_userPathKey) ?? '/';
      _entryPaths['admin'] = prefs.getString(_adminPathKey) ?? '/admin';
      _entryPaths['asyn'] = prefs.getString(_asynPathKey) ?? '/admin/asyn_post.html';
      _entryPaths['ql'] = prefs.getString(_qlPathKey) ?? '/admin/ql_scheduler.html';
    });
  }

  Future<void> _saveConfig(String ip, Map<String, String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverIpKey, ip);
    await prefs.setString(_userPathKey, paths['user']!);
    await prefs.setString(_adminPathKey, paths['admin']!);
    await prefs.setString(_asynPathKey, paths['asyn']!);
    await prefs.setString(_qlPathKey, paths['ql']!);
    setState(() {
      _serverIp = ip;
      _entryPaths.addAll(paths);
    });
  }

  /// 规范路径：保证以 / 开头，空字符串返回 /
  String _normalizePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '/';
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  void _openEntry(Map<String, dynamic> entry) {
    final path = _normalizePath(_entryPaths[entry['id']] ?? '/');
    _channel.invokeMethod('openWebView', {
      'url': 'http://$_serverIp$path',
      'title': entry['name'],
      'serverIp': _serverIp,
      'userPath': _normalizePath(_entryPaths['user']!),
      'adminPath': _normalizePath(_entryPaths['admin']!),
      'asynPath': _normalizePath(_entryPaths['asyn']!),
      'qlPath': _normalizePath(_entryPaths['ql']!),
    });
  }

  /// 重置页面状态 - 当点击底部导航栏内网按钮时调用
  void resetToEntryPage() {
    // 原生 WebView 是独立的 Activity，不需要重置状态
    // 此方法保留用于兼容性
  }

  void _showConfigDialog() {
    _ipController.text = _serverIp;
    _pathControllers.clear();
    for (final id in _entryPaths.keys) {
      _pathControllers[id] = TextEditingController(text: _entryPaths[id]);
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCardBackground : AppTheme.lightCardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.cardRadius)),
        title: Text('服务器配置', style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _ipController,
                decoration: InputDecoration(
                  labelText: '服务器地址',
                  hintText: '例如: 127.0.0.1',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(context.cardRadius)),
                ),
              ),
              SizedBox(height: context.spacingMedium),
              _buildPathField('user', '用户端路径', '例如: /', isDark),
              SizedBox(height: context.spacingMedium),
              _buildPathField('admin', '管理端路径', '例如: /admin', isDark),
              SizedBox(height: context.spacingMedium),
              _buildPathField('asyn', '异步定时路径', '例如: /admin/asyn_post.html', isDark),
              SizedBox(height: context.spacingMedium),
              _buildPathField('ql', 'QL定时路径', '例如: /admin/ql_scheduler.html', isDark),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              var ip = _ipController.text.trim().replaceAll(RegExp(r'^https?://'), '').split('/')[0];
              if (ip.isEmpty) {
                return;
              }
              final paths = <String, String>{};
              for (final id in _entryPaths.keys) {
                paths[id] = _normalizePath(_pathControllers[id]?.text ?? _entryPaths[id]!);
              }
              await _saveConfig(ip, paths);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildPathField(String id, String label, String hint, bool isDark) => TextField(
    controller: _pathControllers[id],
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(context.cardRadius)),
    ),
    style: TextStyle(
      color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(context.spacingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isDark, primaryColor),
              SizedBox(height: context.spacingLarge),
              _buildServerCard(isDark, primaryColor),
              SizedBox(height: context.spacingLarge),
              _buildSectionTitle(primaryColor, '访问入口'),
              SizedBox(height: context.spacingSmall),
              _buildEntryGrid(isDark, primaryColor),
              SizedBox(height: context.spacingLarge),
              _buildTipsCard(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, Color primaryColor) => Row(
    children: [
      Container(
        width: context.iconXLarge,
        height: context.iconXLarge,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [primaryColor, primaryColor.withOpacity(0.7)]),
          borderRadius: BorderRadius.circular(context.cardRadius),
        ),
        child: Icon(Icons.language, color: Colors.white, size: context.iconLarge),
      ),
      SizedBox(width: context.spacingMedium),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('内网访问', style: TextStyle(fontSize: context.fontXLarge, fontWeight: FontWeight.bold, color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)),
            Text('访问内网服务', style: TextStyle(fontSize: context.fontBody, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
          ],
        ),
      ),
    ],
  );

  Widget _buildServerCard(bool isDark, Color primaryColor) => Container(
    decoration: BoxDecoration(
      color: isDark ? AppTheme.darkCardBackground : AppTheme.lightCardBackground,
      borderRadius: BorderRadius.circular(context.cardRadius),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.08), blurRadius: 10, offset: const Offset(0, 4))],
    ),
    padding: ResponsiveUtils.padding(context, all: 16),
    child: Row(
      children: [
        Container(
          width: context.listItemIconContainerSize,
          height: context.listItemIconContainerSize,
          decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(context.cardRadius)),
          child: Icon(Icons.dns_outlined, color: primaryColor, size: context.iconSmall),
        ),
        SizedBox(width: context.spacingMedium),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('服务器地址', style: TextStyle(fontSize: context.fontMedium, fontWeight: FontWeight.w500, color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)),
              Text(_serverIp, style: TextStyle(fontSize: context.fontBody, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
            ],
          ),
        ),
        IconButton(icon: Icon(Icons.edit, color: primaryColor, size: context.iconSmall), onPressed: _showConfigDialog),
      ],
    ),
  );

  Widget _buildSectionTitle(Color color, String title) => Padding(
    padding: EdgeInsets.only(left: context.spacingXSmall / 2),
    child: Text(title, style: TextStyle(fontSize: context.fontBody, fontWeight: FontWeight.w600, color: color)),
  );

  Widget _buildEntryGrid(bool isDark, Color primaryColor) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: context.spacingSmall, mainAxisSpacing: context.spacingSmall, childAspectRatio: 1.2),
    itemCount: _entries.length,
    itemBuilder: (_, index) => _buildEntryCard(_entries[index], isDark, primaryColor),
  );

  Widget _buildEntryCard(Map<String, dynamic> entry, bool isDark, Color primaryColor) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => _openEntry(entry),
      borderRadius: BorderRadius.circular(context.cardRadius),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCardBackground : AppTheme.lightCardBackground,
          borderRadius: BorderRadius.circular(context.cardRadius),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.08), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: context.iconXLarge,
              height: context.iconXLarge,
              decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(context.cardRadius)),
              child: Icon(entry['icon'] as IconData, color: primaryColor, size: context.iconLarge),
            ),
            SizedBox(height: context.spacingSmall),
            Text(entry['name'] as String, style: TextStyle(fontSize: context.fontMedium, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)),
            SizedBox(height: context.spacingXSmall / 2),
            Text(entry['desc'] as String, style: TextStyle(fontSize: context.fontSmall, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)),
          ],
        ),
      ),
    ),
  );

  Widget _buildTipsCard(bool isDark) => Container(
    padding: ResponsiveUtils.padding(context, all: 16),
    decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03), borderRadius: BorderRadius.circular(context.cardRadius)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.info_outline, size: context.iconSmall, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
            SizedBox(width: context.spacingSmall),
            Text('使用说明', style: TextStyle(fontSize: context.fontMedium, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)),
          ],
        ),
        SizedBox(height: context.spacingSmall),
        Text('• 用户端：普通查询服务\n• 管理员：后台管理功能\n• 异步定时：定时任务管理\n• QL定时：青龙面板管理',
          style: TextStyle(fontSize: context.fontSmall, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary, height: 1.6)),
      ],
    ),
  );

  @override
  void dispose() {
    _ipController.dispose();
    for (final controller in _pathControllers.values) {
      controller.dispose();
    }
    _pathControllers.clear();
    super.dispose();
  }
}
