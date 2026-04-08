import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _prefs = SharedPreferences.getInstance();

// ===== Prefs helpers =====
Future<T?> _read<T>(String key, T Function(Map<String, dynamic>) fromJson) async {
  final prefs = await _prefs;
  final raw = prefs.getString(key);
  if (raw == null) return null;
  return fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

Future<void> _write(String key, Map<String, dynamic> json) async {
  final prefs = await _prefs;
  await prefs.setString(key, jsonEncode(json));
}

Future<void> _remove(String key) async {
  final prefs = await _prefs;
  await prefs.remove(key);
}

// ===== Data Classes =====
class ThemeConfigData {
  const ThemeConfigData({this.theme = 'material', this.mode = 'system'});
  final String theme;
  final String mode;
  ThemeConfigData copyWith({String? theme, String? mode}) =>
      ThemeConfigData(theme: theme ?? this.theme, mode: mode ?? this.mode);
  Map<String, dynamic> toJson() => {'theme': theme, 'mode': mode};
  factory ThemeConfigData.fromJson(Map<String, dynamic> j) =>
      ThemeConfigData(
        theme: j['theme'] as String? ?? 'material',
        mode: j['mode'] as String? ?? 'system',
      );
}

class AppLocaleData {
  const AppLocaleData({this.locale = 'ru'});
  final String locale;
  Map<String, dynamic> toJson() => {'locale': locale};
  factory AppLocaleData.fromJson(Map<String, dynamic> j) =>
      AppLocaleData(locale: j['locale'] as String? ?? 'ru');
}

class ProfileData {
  const ProfileData({
    required this.displayName,
    this.fullName = '',
    this.shortDescr = '',
    this.userId,
  });
  final String displayName;
  final String fullName;
  final String shortDescr;
  final int? userId;
  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'fullName': fullName,
        'shortDescr': shortDescr,
        if (userId != null) 'userId': userId,
      };
  factory ProfileData.fromJson(Map<String, dynamic> j) => ProfileData(
        displayName: j['displayName'] as String,
        fullName: j['fullName'] as String? ?? '',
        shortDescr: j['shortDescr'] as String? ?? '',
        userId: j['userId'] as int?,
      );
}

// ===== Providers =====
final persistedThemeProvider = FutureProvider<ThemeConfigData>((ref) async {
  return await _read('theme_config', ThemeConfigData.fromJson) ??
      const ThemeConfigData();
});

final persistedLocaleProvider = FutureProvider<AppLocaleData>((ref) async {
  return await _read('app_locale', AppLocaleData.fromJson) ??
      const AppLocaleData();
});

final persistedProfileProvider = FutureProvider<ProfileData?>((ref) async {
  final prefs = await _prefs;
  if (!(prefs.getBool('profile_created') ?? false)) return null;
  return _read('profile_data', ProfileData.fromJson);
});

Future<void> saveThemeConfig(ThemeConfigData c) async =>
    _write('theme_config', c.toJson());

Future<void> saveAppLocale(AppLocaleData l) async =>
    _write('app_locale', l.toJson());

Future<void> saveProfileData(ProfileData d) async {
  final prefs = await _prefs;
  await prefs.setBool('profile_created', true);
  await _write('profile_data', d.toJson());
}

Future<void> clearProfileData() async {
  await _remove('profile_created');
  await _remove('profile_data');
}
