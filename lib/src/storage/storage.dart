import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

abstract class Storage {
  Future<void> init();

  Future<void> saveDevices(List<Map<String, dynamic>> devices);
  Future<List<Map<String, dynamic>>?> loadDevices();

  Future<void> saveVirtuals(List<Map<String, dynamic>> virtuals);
  Future<List<Map<String, dynamic>>?> loadVirtuals();
}

class SharedPreferencesStorage implements Storage {
  SharedPreferences? _prefs;

  @override
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  @override
  Future<void> saveDevices(List<Map<String, dynamic>> devices) async {
    final str = jsonEncode(devices);
    await _prefs?.setString('ledfx_devices', str);
  }

  @override
  Future<List<Map<String, dynamic>>?> loadDevices() async {
    final str = _prefs?.getString('ledfx_devices');
    if (str == null) return null;
    try {
      final List<dynamic> decoded = jsonDecode(str);
      return decoded.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> saveVirtuals(List<Map<String, dynamic>> virtuals) async {
    final str = jsonEncode(virtuals);
    await _prefs?.setString('ledfx_virtuals', str);
  }

  @override
  Future<List<Map<String, dynamic>>?> loadVirtuals() async {
    final str = _prefs?.getString('ledfx_virtuals');
    if (str == null) return null;
    try {
      final List<dynamic> decoded = jsonDecode(str);
      return decoded.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      return null;
    }
  }
}
