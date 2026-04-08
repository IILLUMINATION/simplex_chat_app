import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'persistent_store.dart';

enum AppLocale {
  english('en'),
  russian('ru');

  const AppLocale(this.code);
  final String code;

  static AppLocale fromCode(String code) {
    for (final l in values) {
      if (l.code == code) return l;
    }
    return AppLocale.english;
  }

  Locale get flutterLocale => Locale(code);
}

class LocaleNotifier extends StateNotifier<AppLocaleData> {
  LocaleNotifier() : super(const AppLocaleData()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('app_locale');
    if (raw != null) {
      try {
        state = AppLocaleData.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
  }

  Future<void> setLocale(AppLocale locale) async {
    state = AppLocaleData(locale: locale.code);
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_locale', jsonEncode(state.toJson()));
  }
}

final localeNotifierProvider =
    StateNotifierProvider<LocaleNotifier, AppLocaleData>((ref) {
  return LocaleNotifier();
});
