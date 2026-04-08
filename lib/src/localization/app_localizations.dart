import 'package:flutter/material.dart';

/// Simple localization map
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const _strings = <String, Map<String, String>>{
    'en': _en,
    'ru': _ru,
  };

  String translate(String key) {
    return _strings[locale.languageCode]?[key] ?? key;
  }

  // ========== Russian ==========
  static const Map<String, String> _ru = {
    'app_title': 'SimpleX Chat',
    'init_core': 'Инициализировать ядро',
    'send': 'Отправить',
    'command_hint': '/_get app settings',
    'command_label': 'Команда',
    'logs_here': 'Логи будут здесь...',
    'core_not_initialized': 'Ядро не инициализировано. Нажмите "Инициализировать ядро".',
    'core_initialized': 'Ядро инициализировано',
    'event_loop_started': 'Event loop запущен',
    'initialization_error': 'Ошибка инициализации',
    'create_profile': 'Создать профиль',
    'profile': 'Профиль',
    'display_name': 'Имя',
    'full_name': 'Полное имя',
    'create': 'Создать',
    'settings': 'Настройки',
    'theme': 'Тема',
    'theme_mode': 'Режим темы',
    'theme_style': 'Стиль темы',
    'language': 'Язык',
    'light': 'Светлая',
    'dark': 'Тёмная',
    'system': 'Системная',
    'material': 'Material',
    'nord': 'Nord',
    'amoled': 'AMOLED',
    'solarized': 'Solarized',
    'english': 'English',
    'russian': 'Русский',
    'contacts': 'Контакты',
    'chats': 'Чаты',
    'no_users': 'Нет пользователей',
    'no_contacts': 'Нет контактов',
    'chat_stopped': 'Чат остановлен',
    'no_chats_yet': 'Пока нет чатов',
    'tap_add_chat': 'Нажмите + чтобы начать',
  };

  // ========== English ==========
  static const Map<String, String> _en = {
    'app_title': 'SimpleX Chat',
    'init_core': 'Init Core',
    'send': 'Send',
    'command_hint': '/_get app settings',
    'command_label': 'Command',
    'logs_here': 'Logs will appear here...',
    'core_not_initialized': 'Core is not initialized. Press "Init Core" first.',
    'core_initialized': 'Core initialized',
    'event_loop_started': 'Event loop started',
    'initialization_error': 'Initialization error',
    'create_profile': 'Create Profile',
    'profile': 'Profile',
    'display_name': 'Display Name',
    'full_name': 'Full Name',
    'create': 'Create',
    'settings': 'Settings',
    'theme': 'Theme',
    'theme_mode': 'Theme Mode',
    'theme_style': 'Theme Style',
    'language': 'Language',
    'light': 'Light',
    'dark': 'Dark',
    'system': 'System',
    'material': 'Material',
    'nord': 'Nord',
    'amoled': 'AMOLED',
    'solarized': 'Solarized',
    'english': 'English',
    'russian': 'Русский',
    'contacts': 'Contacts',
    'chats': 'Chats',
    'no_users': 'No users',
    'no_contacts': 'No contacts',
    'chat_stopped': 'Chat stopped',
    'no_chats_yet': 'No chats yet',
    'tap_add_chat': 'Tap + to get started',
  };
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'ru'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) =>
      Future.value(AppLocalizations(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
