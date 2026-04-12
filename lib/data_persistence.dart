import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network_config.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'dart:io';

class DataPersistence {
  static const String dataKey = 'data-key';
  static const String dataKeyForNative = 'data-key-native';
  static const String vntUniqueIdKey = 'vnt-unique-id-key';

  Future<void> saveData(List<NetworkConfig> configs) async {
    List<String> jsonDataList =
        configs.map((config) => jsonEncode(config.toJson())).toList();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(dataKey, jsonDataList);
    await prefs.setString(dataKeyForNative, jsonEncode(jsonDataList));
  }

  Future<List<NetworkConfig>> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? jsonDataList = prefs.getStringList(dataKey);

    if (jsonDataList != null) {
      return jsonDataList
          .map((jsonData) => NetworkConfig.fromJson(jsonDecode(jsonData)))
          .toList();
    } else {
      return [];
    }
  }

  Future<String> loadUniqueId() async {
    final prefs = await SharedPreferences.getInstance();
    String? uniqueId = prefs.getString(vntUniqueIdKey);
    if (uniqueId == null || uniqueId.isEmpty) {
      uniqueId = const Uuid().v4().toString();
      await prefs.setString(vntUniqueIdKey, uniqueId);
    }
    return uniqueId;
  }

  Future<bool?> loadAutoStart() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is-auto-start');
  }

  Future<void> saveAutoStart(bool autoStart) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is-auto-start', autoStart);
  }

  Future<bool?> loadAutoConnect() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is-auto-connect');
  }

  Future<void> saveAutoConnect(bool autoConnect) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is-auto-connect', autoConnect);
  }

  Future<String?> loadDefaultKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('default-key');
  }

  Future<void> saveDefaultKey(String defaultKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default-key', defaultKey);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<ThemeMode?> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt('theme-mode');
    if (index != null && index >= 0 && index < ThemeMode.values.length) {
      return ThemeMode.values[index];
    }
    return null;
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme-mode', mode.index);
  }

  Future<void> saveCustomThemeColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('custom-theme-color', color.value);
  }

  Future<Color?> loadCustomThemeColor() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt('custom-theme-color');
    if (colorValue != null) {
      return Color(colorValue);
    }
    return null;
  }

  // 导出所有配置到文件
  Future<void> exportAllConfigs(String filePath) async {
    try {
      final configs = await loadData();
      final jsonData = {
        'version': '1.0',
        'export_time': DateTime.now().toIso8601String(),
        'configs': configs.map((c) => c.toJson()).toList(),
      };
      
      final file = File(filePath);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await file.writeAsString(JsonEncoder.withIndent('  ').convert(jsonData));
      debugPrint('配置导出成功: $filePath');
    } catch (e) {
      debugPrint('配置导出失败: $e');
      rethrow;
    }
  }

  // 从文件导入所有配置
  Future<void> importAllConfigs(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在: $filePath');
      }
      final content = await file.readAsString();
      final jsonData = jsonDecode(content);
      final configs = (jsonData['configs'] as List)
          .map((c) => NetworkConfig.fromJson(c))
          .toList();
      await saveData(configs);
      
      if (jsonData.containsKey('theme_mode')) {
        await saveThemeMode(ThemeMode.values[jsonData['theme_mode']]);
      }
      
      if (jsonData.containsKey('custom_theme_color')) {
        await saveCustomThemeColor(Color(jsonData['custom_theme_color']));
      }
      
      if (jsonData.containsKey('auto_start')) {
        await saveAutoStart(jsonData['auto_start']);
      }
      
      if (jsonData.containsKey('auto_connect')) {
        await saveAutoConnect(jsonData['auto_connect']);
      }
      
      if (jsonData.containsKey('default_key')) {
        await saveDefaultKey(jsonData['default_key']);
      }
      
      debugPrint('配置导入成功: $filePath');
    } catch (e) {
      debugPrint('配置导入失败: $e');
      rethrow;
    }
  }
}
