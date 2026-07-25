import 'dart:convert';

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

/// 单个网站配置
class _WebsiteConfig {
  String name;
  String ip;
  String port;
  String path;

  _WebsiteConfig({required this.name, required this.ip, required this.port, required this.path});

  /// 构建基础 URL：非 80 端口时显示端口号
  String get baseUrl {
    final p = port.trim();
    if (p.isEmpty || p == '80') {
      return 'http://$ip';
    }
    return 'http://$ip:$p';
  }

  /// 构建完整访问 URL
  String get fullUrl {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$baseUrl$normalizedPath';
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'ip': ip,
    'port': port,
    'path': path,
  };

  factory _WebsiteConfig.fromJson(Map<String, dynamic> json) => _WebsiteConfig(
    name: json['name'] as String? ?? '未命名',
    ip: json['ip'] as String? ?? '127.0.0.1',
    port: json['port'] as String? ?? '80',
    path: json['path'] as String? ?? '/',
  );
}

class IntranetAccessPageState extends State<IntranetAccessPage> {
  static const String _websitesKey = 'intranet_websites';
  static const MethodChannel _channel = MethodChannel('top.wherewego.vnt/webview');

  final List<_WebsiteConfig> _websites = [];

  @override
  void initState() {
    super.initState();
    _loadWebsites();
  }

  Future<void> _loadWebsites() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_websitesKey);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        setState(() {
          _websites.clear();
          _websites.addAll(list.map((e) => _WebsiteConfig.fromJson(e as Map<String, dynamic>)));
        });
        return;
      } catch (e) {
        // 解析失败时使用默认配置
      }
    }
    // 默认配置
    setState(() {
      _websites.addAll([
        _WebsiteConfig(name: '用户端', ip: '127.0.0.1', port: '80', path: '/'),
        _WebsiteConfig(name: '管理员', ip: '127.0.0.1', port: '80', path: '/admin'),
      ]);
    });
  }

  Future<void> _saveWebsites() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_websites.map((e) => e.toJson()).toList());
    await prefs.setString(_websitesKey, jsonStr);
  }

  /// 规范路径：保证以 / 开头，空字符串返回 /
  String _normalizePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return '/';
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  /// 规范 IP：去除协议头和路径
  String _normalizeIp(String ip) {
    return ip.trim().replaceAll(RegExp(r'^https?://'), '').split('/')[0];
  }

  void _openWebsite(_WebsiteConfig website) {
    _channel.invokeMethod('openWebView', {
      'url': website.fullUrl,
      'title': website.name,
    });
  }

  /// 重置页面状态 - 当点击底部导航栏内网按钮时调用
  void resetToEntryPage() {
    // 原生 WebView 是独立的 Activity，不需要重置状态
    // 此方法保留用于兼容性
  }

  void _showEditDialog({int? index}) {
    final isEdit = index != null;
    final website = isEdit ? _websites[index!] : _WebsiteConfig(name: '', ip: '127.0.0.1', port: '80', path: '/');
    final nameController = TextEditingController(text: website.name);
    final ipController = TextEditingController(text: website.ip);
    final portController = TextEditingController(text: website.port);
    final pathController = TextEditingController(text: website.path);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkCardBackground : AppTheme.lightCardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.cardRadius)),
        title: Text(isEdit ? '编辑网站' : '添加网站', style: TextStyle(color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: '显示名称',
                  hintText: '例如: 闲鱼用户端',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(context.cardRadius)),
                ),
              ),
              SizedBox(height: context.spacingMedium),
              TextField(
                controller: ipController,
                decoration: InputDecoration(
                  labelText: '服务器地址',
                  hintText: '例如: 127.0.0.1',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(context.cardRadius)),
                ),
              ),
              SizedBox(height: context.spacingMedium),
              TextField(
                controller: portController,
                decoration: InputDecoration(
                  labelText: '端口',
                  hintText: '例如: 80',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(context.cardRadius)),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              SizedBox(height: context.spacingMedium),
              TextField(
                controller: pathController,
                decoration: InputDecoration(
                  labelText: '路径',
                  hintText: '例如: / 或 /admin',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(context.cardRadius)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (isEdit)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                _confirmDelete(index!);
              },
              child: const Text('删除', style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              var name = nameController.text.trim();
              if (name.isEmpty) name = '未命名';
              var ip = _normalizeIp(ipController.text);
              if (ip.isEmpty) {
                return;
              }
              var port = portController.text.trim();
              if (port.isEmpty) {
                port = '80';
              }
              final portNumber = int.tryParse(port);
              if (portNumber == null || portNumber < 1 || portNumber > 65535) {
                return;
              }
              final path = _normalizePath(pathController.text);
              final newConfig = _WebsiteConfig(name: name, ip: ip, port: port, path: path);
              setState(() {
                if (isEdit) {
                  _websites[index!] = newConfig;
                } else {
                  _websites.add(newConfig);
                }
              });
              await _saveWebsites();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(int index) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除 "${_websites[index].name}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              setState(() {
                _websites.removeAt(index);
              });
              await _saveWebsites();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

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
              _buildSectionTitle(primaryColor, '网站列表'),
              SizedBox(height: context.spacingSmall),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.35,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _websites.length,
                itemBuilder: (context, index) => _buildWebsiteCard(_websites[index], index, isDark, primaryColor),
              ),
              SizedBox(height: context.spacingMedium),
              _buildAddButton(isDark, primaryColor),
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

  Widget _buildSectionTitle(Color color, String title) => Padding(
    padding: EdgeInsets.only(left: context.spacingXSmall / 2),
    child: Text(title, style: TextStyle(fontSize: context.fontBody, fontWeight: FontWeight.w600, color: color)),
  );

  Widget _buildWebsiteCard(_WebsiteConfig website, int index, bool isDark, Color primaryColor) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => _openWebsite(website),
      borderRadius: BorderRadius.circular(context.cardRadius),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCardBackground : AppTheme.lightCardBackground,
          borderRadius: BorderRadius.circular(context.cardRadius),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.08), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        padding: ResponsiveUtils.padding(context, all: 12),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: Icon(Icons.edit, color: primaryColor, size: context.iconSmall),
                onPressed: () => _showEditDialog(index: index),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.language, color: primaryColor, size: context.iconMedium),
                  SizedBox(height: context.spacingSmall),
                  Text(website.name, style: TextStyle(fontSize: context.fontMedium, fontWeight: FontWeight.w600, color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary), textAlign: TextAlign.center),
                  SizedBox(height: context.spacingXSmall / 2),
                  Text(
                    website.fullUrl,
                    style: TextStyle(fontSize: context.fontSmall, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildAddButton(bool isDark, Color primaryColor) => InkWell(
    onTap: () => _showEditDialog(),
    borderRadius: BorderRadius.circular(context.cardRadius),
    child: Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCardBackground : AppTheme.lightCardBackground,
        borderRadius: BorderRadius.circular(context.cardRadius),
        border: Border.all(color: primaryColor.withOpacity(0.5), width: 1.5),
      ),
      padding: ResponsiveUtils.padding(context, all: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add, color: primaryColor, size: context.iconMedium),
          SizedBox(width: context.spacingSmall),
          Text('添加网站', style: TextStyle(fontSize: context.fontMedium, color: primaryColor, fontWeight: FontWeight.w500)),
        ],
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
        Text('• 点击卡片打开对应网站\n• 每个网站独立配置名称、IP、端口和路径\n• 不同网站使用不同 WebView Activity，互不干扰',
          style: TextStyle(fontSize: context.fontSmall, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary, height: 1.6)),
      ],
    ),
  );
}
