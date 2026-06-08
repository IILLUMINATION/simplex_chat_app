// Chats list screen.
//
// Renders the conversations list, incoming contact requests section, and the
// FAB-driven action sheet (connect via link / create my link).
//
// Styled entirely from the design system — no hardcoded colors or paddings.

import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'design/design.dart';

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  List<ChatPreview> _chats = [];
  List<ContactRequestPreview> _requests = [];
  bool _loading = false;

  /// True after the first successful fetch completes.
  bool _initialLoadDone = false;

  /// Switching profile bumps this so we drop late responses from previous user.
  int _chatsFetchNonce = 0;

  ProfileData? _profile;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    ref.read(fabActionProvider).setHandler(_openActionMenu);
    _loadChats();
    _loadRequests();
    _listenEvents();
  }

  @override
  void dispose() {
    ref.read(fabActionProvider).clearHandler();
    _eventSub?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  void _listenEvents() {
    final service = ref.read(tanglexServiceProvider);
    _eventSub = service.eventStream.listen((event) {
      final result = event['result'];
      if (result is! Map) return;
      final type = result['type'] as String?;

      const refreshTypes = <String>{
        'receivedContactRequest',
        'acceptingContactRequest',
        'contactRequestRejected',
        'chatStarted',
        'activeUser',
        'contactConnection',
        'contact',
        'contactSndReady',
        'contactConnecting',
        'chatItem',
        'chatItemNew',
        'newChatItems',
        'chatItemUpdated',
        'chatItemsDeleted',
        'chatItemsStatusesUpdated',
        'groupChatItemsDeleted',
      };
      if (refreshTypes.contains(type)) _scheduleRefresh();

      if (type == 'contactRequestRejected') {
        final cr = result['contactRequest'];
        if (cr is Map && mounted) {
          final id =
              Map<String, dynamic>.from(cr)['contactRequestId'] as int?;
          if (id != null) {
            setState(() =>
                _requests.removeWhere((r) => r.contactRequestId == id));
          }
        }
      }
      if (type == 'receivedContactRequest') {
        final req = result['contactRequest'];
        if (req is Map) {
          final parsed = ContactRequestPreview.fromJson(
            Map<String, dynamic>.from(req),
          );
          final exists = _requests
              .any((r) => r.contactRequestId == parsed.contactRequestId);
          if (!exists && mounted) {
            setState(() => _requests = [parsed, ..._requests]);
            if (kDebugMode) {
              debugPrint(
                '[Chats] receivedContactRequest id=${parsed.contactRequestId} '
                'contactId_=${parsed.contactId} display=${parsed.displayName}',
              );
            }
          }
        }
      }
    });
  }

  Future<void> _loadChats() async {
    if (_loading) return;
    final token = _chatsFetchNonce;
    setState(() => _loading = true);

    final service = ref.read(tanglexServiceProvider);
    if (!service.isInitialized) {
      if (!mounted || token != _chatsFetchNonce) return;
      setState(() {
        _loading = false;
        _chats = [];
      });
      return;
    }

    final chats = await service.getChats();
    if (!mounted || token != _chatsFetchNonce) return;
    setState(() {
      _chats = chats;
      _loading = false;
      _initialLoadDone = true;
    });
  }

  Future<void> _loadRequests() async {
    final service = ref.read(tanglexServiceProvider);
    if (!service.isInitialized) return;
    final previous = List<ContactRequestPreview>.from(_requests);
    final fromApi = await service.getContactRequests();
    if (!mounted) return;

    // Merge API result with event-driven entries so we don't wipe a request
    // that only exists as an embedded contact row.
    final merged = <int, ContactRequestPreview>{};
    for (final r in fromApi) {
      if (r.contactRequestId != 0) merged[r.contactRequestId] = r;
    }
    for (final r in previous) {
      if (r.contactRequestId != 0) {
        merged.putIfAbsent(r.contactRequestId, () => r);
      }
    }
    final list = merged.values.toList()
      ..sort((a, b) => b.contactRequestId.compareTo(a.contactRequestId));
    setState(() => _requests = list);
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _loadChats();
      _loadRequests();
    });
  }

  // ---------------------------------------------------------------------------
  // FAB / sheets / dialogs
  // ---------------------------------------------------------------------------

  void _openActionMenu() {
    final loc = AppLocalizations.of(context);
    showAppSheet<void>(
      context: context,
      builder: (ctx) => AppSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_rounded),
              title: Text(loc.translate('connect_by_link')),
              onTap: () {
                Navigator.of(ctx).pop();
                _showConnectDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: Text(loc.translate('create_my_link')),
              onTap: () {
                Navigator.of(ctx).pop();
                _createAndShowLink();
              },
            ),
            const SizedBox(height: AppSpacing.s2),
          ],
        ),
      ),
    );
  }

  void _showConnectDialog() {
    final loc = AppLocalizations.of(context);
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface2,
        title: Text(loc.translate('connect_button')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: loc.translate('connection_link_label'),
            hintText: 'smp://...',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.translate('cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final link = controller.text.trim();
              if (link.isEmpty) return;
              final service = ref.read(tanglexServiceProvider);
              final ok = await service.connectViaLink(link);
              if (!mounted) return;
              Navigator.pop(ctx);
              showAppSnack(
                context,
                message: ok
                    ? loc.translate('connection_request_sent')
                    : loc.translate('failed_connect'),
                kind: ok ? AppSnackKind.success : AppSnackKind.error,
              );
              if (ok) await _loadChats();
            },
            child: Text(loc.translate('connect_button')),
          ),
        ],
      ),
    );
  }

  Future<void> _createAndShowLink() async {
    final loc = AppLocalizations.of(context);
    final service = ref.read(tanglexServiceProvider);
    if (!service.isInitialized) {
      showAppSnack(
        context,
        message: loc.translate('core_not_initialized_yet'),
        kind: AppSnackKind.error,
      );
      return;
    }
    final link = await service.createConnectionLink();
    if (!mounted) return;
    if (link == null) {
      showAppSnack(
        context,
        message: loc.translate('failed_create_link'),
        kind: AppSnackKind.error,
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface2,
        title: Text(loc.translate('your_link')),
        content: SelectableText(link, style: AppText.code),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.translate('cancel')),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              Navigator.pop(ctx);
              showAppSnack(
                context,
                message: loc.translate('link_copied'),
                kind: AppSnackKind.success,
              );
            },
            child: Text(loc.translate('copy')),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final service = ref.watch(tanglexServiceProvider);
    final profileAsync = ref.watch(persistedProfileProvider);

    ref.listen<AsyncValue<ProfileData?>>(persistedProfileProvider,
        (prev, next) {
      final nextP = next.asData?.value;
      if (nextP == null) return;
      if (!ref.read(tanglexServiceProvider).isInitialized) return;
      final prevP = prev?.asData?.value;
      if (prevP?.userId == null) return;
      if (prevP!.userId == nextP.userId) return;
      _chatsFetchNonce++;
      if (!mounted) return;
      setState(() {
        _chats = [];
        _requests = [];
        _loading = false;
      });
      _loadChats();
      _loadRequests();
    });

    final chats =
        _chats.where((c) => c.chatType != 'contactRequest').toList();
    final directWithEmbedded =
        chats.where((c) => c.needsAcceptFromDirectRow).toList();
    final embeddedReqIds = directWithEmbedded
        .map((c) => c.embeddedContactRequestId!)
        .toSet();

    final requestsFromChats = _chats
        .where((c) => c.chatType == 'contactRequest')
        .map(
          (c) => ContactRequestPreview(
            contactRequestId: c.chatId ?? 0,
            localDisplayName: c.displayName,
            displayName: c.displayName,
          ),
        )
        .toList();
    final fromApiMerged = [
      ...requestsFromChats,
      ..._requests.where(
        (r) => !requestsFromChats
            .any((x) => x.contactRequestId == r.contactRequestId),
      ),
    ].where((r) => !embeddedReqIds.contains(r.contactRequestId)).toList();
    final fromDirect = directWithEmbedded
        .map(
          (c) => ContactRequestPreview(
            contactRequestId: c.embeddedContactRequestId!,
            localDisplayName: c.displayName,
            displayName: c.displayName,
            contactId: c.chatId,
          ),
        )
        .toList();
    final requestsDisplay = <ContactRequestPreview>[
      ...fromDirect,
      ...fromApiMerged,
    ];

    if (service.isInitialized &&
        !_loading &&
        !_initialLoadDone &&
        _chats.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_loading && !_initialLoadDone) {
          _scheduleRefresh();
        }
      });
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: profileAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
        error: (_, _) => _buildEmpty(loc, service),
        data: (profile) {
          _profile = profile;
          if (!service.isInitialized) {
            return _buildNotInitialized(loc, service);
          }
          if (_loading) return _buildSkeleton();
          if (_chats.isEmpty) return _buildEmpty(loc, service);

          final connectingOnly =
              chats.where((c) => c.isConnectingWithoutRequest).toList();
          final pccChats = chats
              .where((c) => c.chatType == 'contactConnection')
              .toList();
          final pendingInactive = chats.where(
            (c) =>
                c.chatType == 'contact' &&
                c.contactStatus != null &&
                c.contactStatus != 'active',
          );
          final hasIncoming = requestsDisplay.isNotEmpty ||
              connectingOnly.isNotEmpty ||
              pccChats.isNotEmpty ||
              pendingInactive.isNotEmpty;

          final filteredChats = chats.where((c) {
            if (c.chatType == 'contactConnection') return false;
            if (c.needsAcceptFromDirectRow) return false;
            if (c.isConnectingWithoutRequest) return false;
            if (c.chatType == 'contact' &&
                c.contactStatus != null &&
                c.contactStatus != 'active') {
              return false;
            }
            return true;
          }).toList();

          return RefreshIndicator(
            onRefresh: () async {
              await _loadChats();
              await _loadRequests();
            },
            color: AppColors.accent,
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.s2),
              children: [
                if (hasIncoming) ...[
                  _SectionHeader(label: loc.translate('incoming_section')),
                  ...requestsDisplay.map(
                    (req) => _RequestTile(
                      chat: req,
                      avatarBytes: _avatarBytesForRequest(req),
                      onAccept: () => _acceptRequest(req),
                      onReject: () => _rejectRequest(req),
                    ),
                  ),
                  ...connectingOnly.map(
                    (c) => _ConnectingTile(chat: c),
                  ),
                  ...pccChats.map(
                    (c) => _ConnectingTile(chat: c, isPcc: true),
                  ),
                  ...pendingInactive.map((c) => _PendingTile(chat: c)),
                  const AppDivider(),
                ],
                if (filteredChats.isNotEmpty)
                  ...filteredChats.map(
                    (chat) => _ChatTile(
                      chat: chat,
                      onTap: () => _openChat(context, chat),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotInitialized(AppLocalizations loc, TanglexService service) {
    return AppEmptyState(
      icon: Icons.chat_bubble_outline_rounded,
      title: loc.translate('core_not_initialized_chats'),
      action: AppPrimaryButton(
        label: loc.translate('initialize'),
        icon: Icons.play_arrow_rounded,
        onPressed: () async {
          await service.initialize();
          _loadChats();
        },
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.s2),
      children: List.generate(6, (_) => const AppChatTileSkeleton()),
    );
  }

  Widget _buildEmpty(AppLocalizations loc, TanglexService service) {
    return AppEmptyState(
      icon: Icons.chat_bubble_outline_rounded,
      title: loc.translate('no_chats_yet'),
      action: _profile == null
          ? AppPrimaryButton(
              label: loc.translate('create_profile'),
              icon: Icons.person_add_rounded,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateProfileScreen(service: service),
                ),
              ),
            )
          : null,
    );
  }

  Uint8List? _avatarBytesForRequest(ContactRequestPreview r) {
    for (final c in _chats) {
      if (c.chatType == 'contactRequest' && c.chatId == r.contactRequestId) {
        return c.avatarImage;
      }
      if (c.chatType == 'contact' &&
          c.embeddedContactRequestId == r.contactRequestId) {
        return c.avatarImage;
      }
    }
    return null;
  }

  Future<void> _openChat(BuildContext context, ChatPreview chat) async {
    final loc = AppLocalizations.of(context);
    if (chat.chatType != 'contact' && chat.chatType != 'group') {
      showAppSnack(
        context,
        message: loc.translate('chat_not_ready'),
        kind: AppSnackKind.error,
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatRef: chat.chatRef,
          chatName: chat.displayName,
          avatarImage: chat.avatarImage,
          chatType: chat.chatType,
          initialMessagingReady:
              chat.chatType != 'contact' || chat.isMessagingReady,
        ),
      ),
    );
    if (mounted) {
      await _loadChats();
      await _loadRequests();
    }
  }

  Future<void> _acceptRequest(ContactRequestPreview chat) async {
    final reqId = chat.contactRequestId;
    final service = ref.read(tanglexServiceProvider);
    final ok = await service.acceptContactRequest(reqId);
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    showAppSnack(
      context,
      message: ok
          ? loc.translate('request_accepted')
          : loc.translate('failed_accept_request'),
      kind: ok ? AppSnackKind.success : AppSnackKind.error,
    );
    if (ok && mounted) {
      setState(
          () => _requests.removeWhere((r) => r.contactRequestId == reqId));
    }
    await _loadChats();
    await _loadRequests();
  }

  Future<void> _rejectRequest(ContactRequestPreview chat) async {
    final reqId = chat.contactRequestId;
    final service = ref.read(tanglexServiceProvider);
    final ok = await service.rejectContactRequest(reqId);
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    showAppSnack(
      context,
      message: ok
          ? loc.translate('request_rejected')
          : loc.translate('failed_reject_request'),
      kind: ok ? AppSnackKind.success : AppSnackKind.error,
    );
    if (ok && mounted) {
      setState(
          () => _requests.removeWhere((r) => r.contactRequestId == reqId));
    }
    await _loadChats();
    await _loadRequests();
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s4,
        AppSpacing.s4,
        AppSpacing.s2,
      ),
      child: Text(
        label.toUpperCase(),
        style: AppText.meta.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat tile
// ---------------------------------------------------------------------------

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat, required this.onTap});

  final ChatPreview chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final name = chat.displayName.isNotEmpty ? chat.displayName : chat.chatRef;
    final timeStr = _formatTime(chat.timestamp, context);
    final lastMsg = chat.lastMessage.isNotEmpty
        ? chat.lastMessage
        : loc.translate('no_messages_yet');
    final hasUnread = chat.unreadCount > 0;
    final isOutgoing = chat.lastFromMe;
    final previewText =
        isOutgoing ? '${loc.translate('you_label')}: $lastMsg' : lastMsg;
    final isGroup = chat.chatType == 'group';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.accent.withValues(alpha: 0.10),
        highlightColor: AppColors.accent.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppAvatar(
                name: name,
                imageBytes: chat.avatarImage,
                isGroup: isGroup,
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.bodyEmph,
                          ),
                        ),
                        if (timeStr.isNotEmpty)
                          Padding(
                            padding:
                                const EdgeInsets.only(left: AppSpacing.s2),
                            child: Text(
                              timeStr,
                              style: AppText.meta.copyWith(
                                color: hasUnread
                                    ? AppColors.accent
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            previewText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              color: hasUnread
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: AppSpacing.s2),
                          _UnreadBadge(count: chat.unreadCount),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTime(int? ts, BuildContext context) {
    if (ts == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ts ~/ 1000);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(msgDate).inDays;
    final localeName = Localizations.localeOf(context).toLanguageTag();
    if (diff == 0) return DateFormat.Hm(localeName).format(dt);
    if (diff < 7) return DateFormat.E(localeName).format(dt);
    return DateFormat('d.MM', localeName).format(dt);
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: 2,
      ),
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppRadius.rfull),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: AppText.meta.copyWith(
          color: AppColors.textOnAccent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connecting / pending / request tiles
// ---------------------------------------------------------------------------

class _ConnectingTile extends StatelessWidget {
  const _ConnectingTile({required this.chat, this.isPcc = false});

  final ChatPreview chat;
  final bool isPcc;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final title = chat.displayName.isNotEmpty
        ? chat.displayName
        : loc.translate('pending');
    final subtitle = isPcc
        ? loc.translate('pending_link_connection_hint')
        : loc.translate('connecting_secure_hint');

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: AppRadius.brm,
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s3,
      ),
      child: Row(
        children: [
          AppAvatar(name: title, imageBytes: chat.avatarImage),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isPcc
                      ? loc.translate('pending_link_connection')
                      : loc.translate('connecting_secure'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyEmph,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.chat,
    required this.onAccept,
    required this.onReject,
    this.avatarBytes,
  });

  final ContactRequestPreview chat;
  final Uint8List? avatarBytes;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final title = chat.displayName.isNotEmpty
        ? chat.displayName
        : (chat.localDisplayName.isNotEmpty
            ? chat.localDisplayName
            : loc.translate('request'));
    final parts = <String>[
      if (chat.fullName.isNotEmpty) chat.fullName,
      if (chat.shortDescr.isNotEmpty) chat.shortDescr,
    ];
    final subtitle =
        parts.isEmpty ? loc.translate('wants_to_connect') : parts.join(' · ');

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: AppRadius.brm,
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              AppAvatar(name: title, imageBytes: avatarBytes),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyEmph,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onReject,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                ),
                child: Text(loc.translate('reject')),
              ),
              const SizedBox(width: AppSpacing.s2),
              FilledButton(
                onPressed: onAccept,
                child: Text(loc.translate('accept')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PendingTile extends StatelessWidget {
  const _PendingTile({required this.chat});

  final ChatPreview chat;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final title = chat.displayName.isNotEmpty
        ? chat.displayName
        : loc.translate('pending');
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: AppRadius.brm,
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s3,
      ),
      child: Row(
        children: [
          AppAvatar(name: title, imageBytes: chat.avatarImage),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppText.bodyEmph,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  loc.translate('pending_acceptance'),
                  style: AppText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
