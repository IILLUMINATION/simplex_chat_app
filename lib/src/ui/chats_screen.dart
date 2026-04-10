import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../main.dart';
import '../localization/app_localizations.dart';
import '../providers/persistent_store.dart';
import '../service/tanglex_service.dart';
import 'chat_screen.dart';
import 'create_profile_screen.dart';

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
    _loadChats();
    _loadRequests();
    _listenEvents();
  }

  @override
  void dispose() {
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

    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _buildEmpty(loc, service),
      data: (profile) {
        _profile = profile;

        if (!service.isInitialized) {
          return _buildNotInitialized(loc, service);
        }

        if (_loading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (_chats.isEmpty) {
          return _buildEmpty(loc, service);
        }

        return RefreshIndicator(
          onRefresh: _loadChats,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (requests.isNotEmpty || pendingDirects.isNotEmpty) ...[
                _SectionHeader(
                  title: loc.translate('requests'),
                  subtitle: loc.translate('incoming_contact_requests'),
                ),
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
                const SizedBox(height: 8),
              ],
              if (chats.isNotEmpty) ...[
                _SectionHeader(
                  title: loc.translate('chats'),
                  subtitle: loc.translate('your_conversations'),
                ),
                ...chats.where((c) =>
                        !(c.chatType == 'contact' &&
                            (c.contactStatus != null &&
                                c.contactStatus != 'active')))
                    .map((chat) => _ChatTile(
                          chat: chat,
                          onTap: () => _openChat(context, chat),
                        )),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotInitialized(AppLocalizations loc, TanglexService service) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80,
              color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            loc.translate('core_not_initialized_chats'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
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
          Icon(Icons.chat_bubble_outline, size: 80,
              color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            loc.translate('no_chats_yet'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
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
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
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
      final cs = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? loc.translate('request_accepted') : loc.translate('failed_accept_request')),
          backgroundColor: ok ? cs.onInverseSurface : cs.error,
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
      final cs = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? loc.translate('request_rejected') : loc.translate('failed_reject_request')),
          backgroundColor: ok ? cs.onInverseSurface : cs.error,
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

class _ChatTile extends StatelessWidget {
  final ChatPreview chat;
  final VoidCallback onTap;

  const _ChatTile({required this.chat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final timeStr = chat.timestamp != null
        ? DateFormat.Hm().format(DateTime.fromMillisecondsSinceEpoch(chat.timestamp! ~/ 1000))
        : '';
    final initials = _initials(chat.displayName.isNotEmpty ? chat.displayName : chat.chatRef);
    final avatarBg = chat.chatType == 'group'
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.primaryContainer;
    final avatarFg = chat.chatType == 'group'
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onPrimaryContainer;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: avatarBg,
        backgroundImage:
            chat.avatarImage != null ? MemoryImage(chat.avatarImage!) : null,
        child: chat.avatarImage == null
            ? Text(
                initials,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: avatarFg,
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
      ),
      title: Text(
        chat.displayName.isNotEmpty ? chat.displayName : chat.chatRef,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        chat.lastMessage.isNotEmpty ? chat.lastMessage : loc.translate('no_messages_yet'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
      trailing: chat.unreadCount > 0
          ? Badge(label: Text('${chat.unreadCount}'))
          : (timeStr.isNotEmpty ? Text(timeStr, style: theme.textTheme.bodySmall) : null),
      onTap: onTap,
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
    final theme = Theme.of(context);
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: theme.colorScheme.secondaryContainer,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: theme.colorScheme.secondary,
              child: Text(
                initials,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSecondary,
                  fontWeight: FontWeight.w700,
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
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onReject,
              child: Text(loc.translate('reject')),
            ),
            const SizedBox(width: 6),
            FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onAccept,
              child: Text(loc.translate('accept')),
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
    final theme = Theme.of(context);
    final title = chat.displayName.isNotEmpty ? chat.displayName : loc.translate('pending');
    final initials = _initials(title);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.surfaceContainerHighest,
      elevation: 0,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          backgroundImage:
              chat.avatarImage != null ? MemoryImage(chat.avatarImage!) : null,
          child: chat.avatarImage == null
              ? Text(
                  initials,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
        title: Text(title),
        subtitle: Text(
          loc.translate('pending_acceptance'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
