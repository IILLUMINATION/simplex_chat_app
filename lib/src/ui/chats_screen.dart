import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../main.dart';
import '../localization/app_localizations.dart';
import '../providers/persistent_store.dart';
import '../service/tanglex_service.dart';
import 'chat_screen.dart';
import 'create_profile_screen.dart';

// Dark theme colors matching chat_screen.dart
const _kBgColor = Color(0xFF000000);
const _kSurfaceColor = Color(0xFF111111);
const _kTileColor = Color(0xFF191919);
const _kTextPrimary = Color(0xFFE8E8E8);
const _kTextSecondary = Color(0xFF808080);
const _kHintText = Color(0xFF606060);
const _kDivider = Color(0xFF333333);
const _kAccent = Color(0xFF5A9CF5);
const _kAvatarBg = Color(0xFF2A2A2A);
const _kBorder = Color(0xFF3A3A3A);
const _kQuotedBg = Color(0xFF303030);

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  List<ChatPreview> _chats = [];
  List<ContactRequestPreview> _requests = [];
  bool _loading = false;
  ProfileData? _profile;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    // Register FAB handler
    ref.read(fabActionProvider).setHandler(_openActionMenu);
    _loadChats();
    _loadRequests();
    _listenEvents();
  }

  @override
  void dispose() {
    // Unregister FAB handler
    ref.read(fabActionProvider).clearHandler();
    _eventSub?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }

  void _listenEvents() {
    final service = ref.read(tanglexServiceProvider);
    _eventSub = service.eventStream.listen((event) {
      final result = event['result'];
      if (result is Map) {
        final type = result['type'] as String?;
        if (type == 'receivedContactRequest' ||
            type == 'acceptingContactRequest' ||
            type == 'contactRequestRejected' ||
            type == 'chatStarted' ||
            type == 'activeUser' ||
            type == 'contactConnection' ||
            type == 'contact' ||
            type == 'chatItem' ||
            type == 'chatItemNew') {
          _scheduleRefresh();
        }
        if (type == 'receivedContactRequest') {
          final req = result['contactRequest'];
          if (req is Map) {
            final parsed = ContactRequestPreview.fromJson(
              Map<String, dynamic>.from(req),
            );
            final exists = _requests.any(
              (r) => r.contactRequestId == parsed.contactRequestId,
            );
            if (!exists && mounted) {
              setState(() => _requests = [parsed, ..._requests]);
            }
          }
        }
      }
    });
  }

  Future<void> _loadChats() async {
    if (_loading) return;
    setState(() => _loading = true);

    final service = ref.read(tanglexServiceProvider);
    if (!service.isInitialized) {
      setState(() {
        _loading = false;
        _chats = [];
      });
      return;
    }

    final chats = await service.getChats();
    setState(() {
      _chats = chats;
      _loading = false;
    });
  }

  Future<void> _loadRequests() async {
    final service = ref.read(tanglexServiceProvider);
    if (!service.isInitialized) return;
    final requests = await service.getContactRequests();
    if (!mounted) return;
    setState(() => _requests = requests);
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        _loadChats();
      }
    });
  }

  void _openActionMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kSurfaceColor,
      showDragHandle: true,
      builder: (ctx) => _ActionMenuSheet(
        onConnectViaLink: () {
          Navigator.of(ctx).pop();
          _showConnectDialog();
        },
        onCreateLink: () {
          Navigator.of(ctx).pop();
          _createAndShowLink();
        },
      ),
    );
  }

  void _showConnectDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSurfaceColor,
        title: Text(
          AppLocalizations.of(context).translate('connect_button'),
          style: const TextStyle(color: _kTextPrimary),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: _kTextPrimary),
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context).translate('connection_link_label'),
            hintText: 'smp://...',
            hintStyle: const TextStyle(color: _kHintText),
            labelStyle: const TextStyle(color: _kTextSecondary),
            border: const OutlineInputBorder(borderSide: BorderSide(color: _kBorder)),
            enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: _kBorder)),
            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: _kAccent)),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.of(context).translate('cancel'),
              style: const TextStyle(color: _kTextSecondary),
            ),
          ),
          FilledButton(
            onPressed: () async {
              final link = controller.text.trim();
              if (link.isEmpty) return;
              final service = ref.read(tanglexServiceProvider);
              final ok = await service.connectViaLink(link);
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? AppLocalizations.of(context).translate('connection_request_sent')
                          : AppLocalizations.of(context).translate('failed_connect'),
                    ),
                    backgroundColor: ok ? _kTileColor : const Color(0xFFCF6679),
                  ),
                );
                if (ok) await _loadChats();
              }
            },
            child: Text(AppLocalizations.of(context).translate('connect_button')),
          ),
        ],
      ),
    );
  }

  Future<void> _createAndShowLink() async {
    final service = ref.read(tanglexServiceProvider);
    if (!service.isInitialized) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).translate('core_not_initialized_yet')),
          backgroundColor: const Color(0xFFCF6679),
        ),
      );
      return;
    }
    final loc = AppLocalizations.of(context);
    final link = await service.createConnectionLink();
    if (!mounted) return;
    if (link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.translate('failed_create_link')),
          backgroundColor: const Color(0xFFCF6679),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSurfaceColor,
        title: Text(loc.translate('your_link'), style: const TextStyle(color: _kTextPrimary)),
        content: SelectableText(
          link,
          style: const TextStyle(color: _kTextPrimary, fontFamily: 'monospace', fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.translate('cancel'), style: const TextStyle(color: _kTextSecondary)),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(loc.translate('link_copied')),
                  backgroundColor: _kTileColor,
                ),
              );
            },
            child: Text(loc.translate('copy'), style: const TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final service = ref.watch(tanglexServiceProvider);
    final profileAsync = ref.watch(persistedProfileProvider);
    final requestsFromChats = _chats
        .where((c) => c.chatType == 'contactRequest')
        .map((c) => ContactRequestPreview(
              contactRequestId: c.chatId ?? 0,
              localDisplayName: c.displayName,
              displayName: c.displayName,
            ))
        .toList();
    final requestsByContactId = {
      for (final r in _requests) if (r.contactId != null) r.contactId!: r,
    };
    final requests = [
      ...requestsFromChats,
      ..._requests.where((r) => !requestsFromChats
          .any((x) => x.contactRequestId == r.contactRequestId)),
    ];
    final chats = _chats.where((c) => c.chatType != 'contactRequest').toList();
    final pendingDirects = chats.where((c) =>
        c.chatType == 'contact' &&
        (c.contactStatus != null && c.contactStatus != 'active'));

    if (service.isInitialized && !_loading && _chats.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_loading) {
          _scheduleRefresh();
        }
      });
    }

    return Scaffold(
      backgroundColor: _kBgColor,
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: _kAccent)),
        error: (e, st) => _buildEmpty(loc, service),
        data: (profile) {
          _profile = profile;

          if (!service.isInitialized) {
            return _buildNotInitialized(loc, service);
          }

          if (_loading) {
            return const Center(child: CircularProgressIndicator(color: _kAccent));
          }

          if (_chats.isEmpty) {
            return _buildEmpty(loc, service);
          }

          final filteredChats = chats.where((c) =>
              !(c.chatType == 'contact' &&
                  (c.contactStatus != null && c.contactStatus != 'active'))).toList();

          return RefreshIndicator(
            onRefresh: _loadChats,
            color: _kAccent,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                if (requests.isNotEmpty || pendingDirects.isNotEmpty) ...[
                  ...requests.map((req) => _RequestTile(
                        chat: req,
                        onAccept: () => _acceptRequest(req),
                        onReject: () => _rejectRequest(req),
                      )),
                  ...pendingDirects.map((c) {
                    final req = requestsByContactId[c.chatId];
                    if (req != null) {
                      return _RequestTile(
                        chat: req,
                        onAccept: () => _acceptRequest(req),
                        onReject: () => _rejectRequest(req),
                      );
                    }
                    return _PendingTile(chat: c);
                  }),
                  const Divider(color: _kDivider, height: 1),
                ],
                if (filteredChats.isNotEmpty) ...[
                  ...filteredChats.map((chat) => _ChatTile(
                        chat: chat,
                        onTap: () => _openChat(context, chat),
                      )),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotInitialized(AppLocalizations loc, TanglexService service) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.chat_bubble_outline, size: 80, color: _kTextSecondary),
          const SizedBox(height: 16),
          Text(
            loc.translate('core_not_initialized_chats'),
            style: const TextStyle(
              fontSize: 16,
              color: _kTextSecondary,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              await service.initialize();
              _loadChats();
            },
            icon: const Icon(Icons.play_arrow),
            label: Text(loc.translate('initialize')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations loc, TanglexService service) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.chat_bubble_outline, size: 80, color: _kTextSecondary),
          const SizedBox(height: 16),
          Text(
            loc.translate('no_chats_yet'),
            style: const TextStyle(
              fontSize: 16,
              color: _kTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (_profile == null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateProfileScreen(service: service),
                ),
              ),
              icon: const Icon(Icons.person_add),
              label: Text(loc.translate('create_profile')),
            ),
          ],
        ],
      ),
    );
  }

  void _openChat(BuildContext context, ChatPreview chat) async {
    final loc = AppLocalizations.of(context);
    if (chat.chatType != 'contact' && chat.chatType != 'group') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.translate('chat_not_ready')),
          backgroundColor: const Color(0xFFCF6679),
        ),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatRef: chat.chatRef,
          chatName: chat.displayName,
          avatarImage: chat.avatarImage,
          chatType: chat.chatType,
        ),
      ),
    );
    // Refresh chat list after returning from chat
    if (mounted) {
      await _loadChats();
      await _loadRequests();
    }
  }

  Future<void> _acceptRequest(ContactRequestPreview chat) async {
    final reqId = chat.contactRequestId;
    final service = ref.read(tanglexServiceProvider);
    final ok = await service.acceptContactRequest(reqId);
    if (mounted) {
      final loc = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? loc.translate('request_accepted') : loc.translate('failed_accept_request')),
          backgroundColor: ok ? _kTileColor : const Color(0xFFCF6679),
        ),
      );
    }
    if (ok && mounted) {
      setState(() =>
          _requests.removeWhere((r) => r.contactRequestId == reqId));
    }
    await _loadChats();
  }

  Future<void> _rejectRequest(ContactRequestPreview chat) async {
    final reqId = chat.contactRequestId;
    final service = ref.read(tanglexServiceProvider);
    final ok = await service.rejectContactRequest(reqId);
    if (mounted) {
      final loc = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? loc.translate('request_rejected') : loc.translate('failed_reject_request')),
          backgroundColor: ok ? _kTileColor : const Color(0xFFCF6679),
        ),
      );
    }
    if (ok && mounted) {
      setState(() =>
          _requests.removeWhere((r) => r.contactRequestId == reqId));
    }
    await _loadChats();
  }
}

/// FAB action sheet
class _ActionMenuSheet extends StatelessWidget {
  final VoidCallback onConnectViaLink;
  final VoidCallback onCreateLink;

  const _ActionMenuSheet({
    required this.onConnectViaLink,
    required this.onCreateLink,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.qr_code_scanner, color: _kTextPrimary),
            title: Text(
              loc.translate('connect_by_link'),
              style: const TextStyle(color: _kTextPrimary),
            ),
            onTap: onConnectViaLink,
          ),
          const Divider(color: _kDivider, height: 1),
          ListTile(
            leading: const Icon(Icons.share, color: _kTextPrimary),
            title: Text(
              loc.translate('create_my_link'),
              style: const TextStyle(color: _kTextPrimary),
            ),
            onTap: onCreateLink,
          ),
        ],
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final ChatPreview chat;
  final VoidCallback onTap;

  const _ChatTile({required this.chat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final timeStr = _formatTime(chat.timestamp);
    final initials = _initials(chat.displayName.isNotEmpty ? chat.displayName : chat.chatRef);
    final lastMsg = chat.lastMessage.isNotEmpty
        ? chat.lastMessage
        : loc.translate('no_messages_yet');
    final hasUnread = chat.unreadCount > 0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            _AvatarWidget(
              imageBytes: chat.avatarImage,
              initials: initials,
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: name + time/badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat.displayName.isNotEmpty
                              ? chat.displayName
                              : chat.chatRef,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _kTextPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Time + badge column
                      if (hasUnread)
                        _Badge(count: chat.unreadCount)
                      else if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style: const TextStyle(
                            color: _kTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  // Bottom row: message preview
                  Text(
                    lastMsg,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasUnread ? _kTextPrimary : _kTextSecondary,
                      fontSize: 13.5,
                      fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int? ts) {
    if (ts == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts ~/ 1000);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDate).inDays;
    if (diff == 0) {
      return DateFormat.Hm().format(dt);
    } else if (diff == 1) {
      return _weekdayShort(dt);
    } else if (diff < 7) {
      return _weekdayShort(dt);
    } else {
      return '${dt.day}.${dt.month.toString().padLeft(2, '0')}';
    }
  }

  String _weekdayShort(DateTime dt) {
    const days = ['вс', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб'];
    return days[dt.weekday % 7];
  }
}

class _AvatarWidget extends StatelessWidget {
  final Uint8List? imageBytes;
  final String initials;

  const _AvatarWidget({
    required this.imageBytes,
    required this.initials,
  });

  @override
  Widget build(BuildContext context) {
    const size = 50.0;
    Widget avatar;
    if (imageBytes != null && imageBytes!.isNotEmpty) {
      avatar = ClipOval(
        child: Image.memory(
          imageBytes!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialsCircle(),
        ),
      );
    } else {
      avatar = _initialsCircle();
    }
    return SizedBox(width: size, height: size, child: avatar);
  }

  Widget _initialsCircle() {
    final colors = [
      const Color(0xFF5A9CF5),
      const Color(0xFF6BC56E),
      const Color(0xFFF5A623),
      const Color(0xFFF06292),
      const Color(0xFF9575CD),
      const Color(0xFF4DD0E1),
    ];
    final colorIndex = initials.runes.fold<int>(0, (prev, r) => prev + r) % colors.length;
    return CircleAvatar(
      radius: 25,
      backgroundColor: colors[colorIndex],
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;

  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: const BoxDecoration(
        color: _kAccent,
        shape: BoxShape.circle,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  String firstChar(String s) =>
      String.fromCharCode(s.runes.isNotEmpty ? s.runes.first : 63);
  if (parts.length == 1) {
    return firstChar(parts.first).toUpperCase();
  }
  final first = firstChar(parts.first).toUpperCase();
  final last = firstChar(parts.last).toUpperCase();
  return '$first$last';
}

class _RequestTile extends StatelessWidget {
  final ContactRequestPreview chat;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _RequestTile({
    required this.chat,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final title = chat.displayName.isNotEmpty
        ? chat.displayName
        : (chat.localDisplayName.isNotEmpty ? chat.localDisplayName : loc.translate('request'));
    final initials = _initials(title);
    final parts = <String>[
      if (chat.fullName.isNotEmpty) chat.fullName,
      if (chat.shortDescr.isNotEmpty) chat.shortDescr,
    ];
    final subtitle = parts.isEmpty
        ? loc.translate('wants_to_connect')
        : parts.join(' · ');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _kQuotedBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: _kAvatarBg,
              child: Text(
                initials,
                style: const TextStyle(
                  color: _kTextPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _kTextPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _kTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kBorder),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onReject,
              child: Text(
                loc.translate('reject'),
                style: const TextStyle(color: _kTextSecondary),
              ),
            ),
            const SizedBox(width: 6),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _kAccent,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onAccept,
              child: Text(
                loc.translate('accept'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingTile extends StatelessWidget {
  final ChatPreview chat;

  const _PendingTile({required this.chat});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final title = chat.displayName.isNotEmpty ? chat.displayName : loc.translate('pending');
    final initials = _initials(title);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _kQuotedBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _kAvatarBg,
          backgroundImage:
              chat.avatarImage != null ? MemoryImage(chat.avatarImage!) : null,
          child: chat.avatarImage == null
              ? Text(
                  initials,
                  style: const TextStyle(
                    color: _kTextPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                )
              : null,
        ),
        title: Text(
          title,
          style: const TextStyle(color: _kTextPrimary),
        ),
        subtitle: Text(
          loc.translate('pending_acceptance'),
          style: const TextStyle(
            color: _kTextSecondary,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _kTextPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: _kTextSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
