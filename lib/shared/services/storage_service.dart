import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  static StorageService get instance => _instance;

  StorageService._internal();

  late SharedPreferences _prefs;
  late FlutterSecureStorage _secureStorage;
  late Box _generalBox;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _secureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    );
    _generalBox = await Hive.openBox('vortex_general');
  }

  // Secure Storage (for tokens, passwords)
  Future<void> setSecure(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }

  Future<String?> getSecure(String key) async {
    return await _secureStorage.read(key: key);
  }

  Future<void> deleteSecure(String key) async {
    await _secureStorage.delete(key: key);
  }

  Future<void> clearSecure() async {
    await _secureStorage.deleteAll();
  }

  // SharedPreferences (for simple key-value)
  Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  bool? getBool(String key) {
    return _prefs.getBool(key);
  }

  Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  String? getString(String key) {
    return _prefs.getString(key);
  }

  Future<void> setInt(String key, int value) async {
    await _prefs.setInt(key, value);
  }

  int? getInt(String key) {
    return _prefs.getInt(key);
  }

  // Hive (for complex objects)
  Future<void> putObject(String key, dynamic value) async {
    await _generalBox.put(key, value);
  }

  dynamic getObject(String key) {
    return _generalBox.get(key);
  }

  Future<void> deleteObject(String key) async {
    await _generalBox.delete(key);
  }

  // Clear all data
  Future<void> clearAll() async {
    await _prefs.clear();
    await _secureStorage.deleteAll();
    await _generalBox.clear();
  }
}
