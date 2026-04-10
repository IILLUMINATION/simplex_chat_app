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
    'app_title': 'TangleX Chat',
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
    'connect': 'Подключения',
    'connect_by_link': 'По ссылке',
    'my_link': 'Моя ссылка',

    // Chats screen
    'requests': 'Запросы',
    'incoming_contact_requests': 'Входящие запросы контактов',
    'your_conversations': 'Ваши диалоги',
    'core_not_initialized_chats': 'Ядро не инициализировано',
    'initialize': 'Инициализировать',
    'chat_not_ready': 'Этот чат пока не готов',
    'request_accepted': 'Запрос принят',
    'failed_accept_request': 'Не удалось принять запрос',
    'request_rejected': 'Запрос отклонён',
    'failed_reject_request': 'Не удалось отклонить запрос',
    'no_messages_yet': 'Пока нет сообщений',
    'request': 'Запрос',
    'wants_to_connect': 'Хочет связаться с вами',
    'reject': 'Отклонить',
    'accept': 'Принять',
    'pending': 'В ожидании',
    'pending_acceptance': 'Ожидает принятия',

    // Connect screen
    'core_not_initialized_yet': 'Ядро ещё не инициализировано',
    'connection_request_sent': 'Запрос на подключение отправлен!',
    'failed_connect': 'Не удалось подключиться. Проверьте логи.',
    'failed_create_link': 'Не удалось создать ссылку. Проверьте логи.',
    'paste_link_description': 'Вставьте ссылку от контакта, чтобы начать общение.',
    'connection_link_label': 'Ссылка для подключения',
    'connect_button': 'Подключиться',
    'create_link_description': 'Создайте свою ссылку и поделитесь с кем угодно.',
    'create_my_link': 'Создать мою ссылку',
    'your_link': 'Ваша ссылка:',
    'link_copied': 'Ссылка скопирована!',
    'copy': 'Копировать',
    'share': 'Поделиться',

    // Profile screen
    'no_profile_yet': 'Профиля пока нет',
    'create_profile_description': 'Создайте профиль, чтобы начать общение',
    'user_id': 'ID пользователя',
    'create_new_profile': 'Создать новый профиль',
    'create_new_profile_hint': 'Если хотите новый профиль, сначала удалите текущий',
    'refresh': 'Обновить',
    'delete_profile': 'Удалить профиль',
    'delete_profile_hint': 'Удаляет активного пользователя из ядра',
    'profiles': 'Профили',
    'user_id_value': 'ID пользователя: %s',
    'active': 'Активный',
    'activate': 'Активировать',
    'delete_profile_confirm': 'Удалить профиль?',
    'delete_profile_warning': 'Это удалит профиль из ядра TangleX. Вы сможете создать новый.',
    'cancel': 'Отмена',
    'delete': 'Удалить',
    'profile_deleted': 'Профиль удалён',
    'failed_delete_profile': 'Не удалось удалить профиль',
    'profile_updated': 'Профиль обновлён',
    'failed_switch_profile': 'Не удалось переключить профиль',

    // Create profile screen
    'display_name_required': 'Имя обязательно',
    'bio': 'О себе',
    'bio_hint': 'Пара слов о себе...',
    'profile_created': '✓ Профиль создан',

    // Chat screen
    'failed_send_video': 'Не удалось отправить видео',
    'failed_send_file': 'Не удалось отправить файл',
    'failed_send_sticker': 'Не удалось отправить стикер',
    'failed_send_circle': 'Не удалось отправить кружок',
    'failed_send_error': 'Не удалось отправить: %s',
    'new_sticker_pack': 'Новый стикер-пак',
    'sticker_name': 'Название',
    'sticker_id': 'ID (латиница)',
    'sticker_author': 'Автор (необяз.)',
    'sticker_next': 'Далее',
    'photo': 'Фото',
    'video': 'Видео',
    'audio': 'Аудио',
    'file': 'Файл',
    'hd_download': 'HD download',
    'hd_download_tooltip': 'HD download (unstable)',
    'hd_download_warning': 'Включай только если нужно: может крэшить native core.',
    'sticker_not_installed': 'Стикеры не установлены',
    'import': 'Импортировать',
    'chat_started': 'Чат начат',
    'video_not_loaded': 'Видео ещё не загружено.',
    'preview_error': 'Не удалось сделать превью',
    'circle': 'Кружок',
    'message_hint': 'Сообщение...',
    'debug_console': 'Debug-консоль',
    'initializing': 'Инициализация...',
  };

  // ========== English ==========
  static const Map<String, String> _en = {
    'app_title': 'TangleX Chat',
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
    'connect': 'Connect',
    'connect_by_link': 'By link',
    'my_link': 'My link',

    // Chats screen
    'requests': 'Requests',
    'incoming_contact_requests': 'Incoming contact requests',
    'your_conversations': 'Your conversations',
    'core_not_initialized_chats': 'Core not initialized',
    'initialize': 'Initialize',
    'chat_not_ready': 'This chat is not ready yet',
    'request_accepted': 'Request accepted',
    'failed_accept_request': 'Failed to accept request',
    'request_rejected': 'Request rejected',
    'failed_reject_request': 'Failed to reject request',
    'no_messages_yet': 'No messages yet',
    'request': 'Request',
    'wants_to_connect': 'Wants to connect with you',
    'reject': 'Reject',
    'accept': 'Accept',
    'pending': 'Pending',
    'pending_acceptance': 'Pending acceptance',

    // Connect screen
    'core_not_initialized_yet': 'Core is not initialized yet',
    'connection_request_sent': 'Connection request sent!',
    'failed_connect': 'Failed to connect. Check the logs for details.',
    'failed_create_link': 'Failed to create link. Check the logs for details.',
    'paste_link_description': 'Paste a connection link from your contact to start a conversation.',
    'connection_link_label': 'Connection link',
    'connect_button': 'Connect',
    'create_link_description': 'Create your connection link and share it with anyone you want to chat with.',
    'create_my_link': 'Create my link',
    'your_link': 'Your link:',
    'link_copied': 'Link copied!',
    'copy': 'Copy',
    'share': 'Share',

    // Profile screen
    'no_profile_yet': 'No profile yet',
    'create_profile_description': 'Create a profile to start messaging',
    'user_id': 'User ID',
    'create_new_profile': 'Create new profile',
    'create_new_profile_hint': 'If you want a new profile, delete current first',
    'refresh': 'Refresh',
    'delete_profile': 'Delete profile',
    'delete_profile_hint': 'Removes active user from the core',
    'profiles': 'Profiles',
    'user_id_value': 'User ID: %s',
    'active': 'Active',
    'activate': 'Activate',
    'delete_profile_confirm': 'Delete profile?',
    'delete_profile_warning': 'This will delete the active user profile in the TangleX core. You can create a new one after.',
    'cancel': 'Cancel',
    'delete': 'Delete',
    'profile_deleted': 'Profile deleted',
    'failed_delete_profile': 'Failed to delete profile',
    'profile_updated': 'Active profile updated',
    'failed_switch_profile': 'Failed to switch profile',

    // Create profile screen
    'display_name_required': 'Display name is required',
    'bio': 'Bio',
    'bio_hint': 'A few words about yourself...',
    'profile_created': '✓ Profile created',

    // Chat screen
    'failed_send_video': 'Failed to send video',
    'failed_send_file': 'Failed to send file',
    'failed_send_sticker': 'Failed to send sticker',
    'failed_send_circle': 'Failed to send circle video',
    'failed_send_error': 'Failed to send: %s',
    'new_sticker_pack': 'New sticker pack',
    'sticker_name': 'Name',
    'sticker_id': 'ID (Latin)',
    'sticker_author': 'Author (optional)',
    'sticker_next': 'Next',
    'photo': 'Photo',
    'video': 'Video',
    'audio': 'Audio',
    'file': 'File',
    'hd_download': 'HD download',
    'hd_download_tooltip': 'HD download (unstable)',
    'hd_download_warning': 'Enable only if needed: may crash native core.',
    'sticker_not_installed': 'No stickers installed',
    'import': 'Import',
    'chat_started': 'Chat started',
    'video_not_loaded': 'Video is not loaded yet.',
    'preview_error': 'Failed to create preview',
    'circle': 'Circle',
    'message_hint': 'Message...',
    'debug_console': 'Debug Console',
    'initializing': 'Initializing...',
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
