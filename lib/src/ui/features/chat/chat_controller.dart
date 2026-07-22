// TangleX — single-chat controller.
//
// Owns the message list for one chatRef. Subscribes to TanglexService.events,
// patches/appends/removes UiMessage entries on the fly. Per HANDOFF.md § 6 we
// debounce repeated refreshes from bursts of events.
//
// Family parameter: chatRef ('@<id>' or '#<id>'). When the screen is closed
// the autoDispose kicks in and the event subscription is dropped.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart';
import '../../../data/chat_message_parser.dart';
import '../../../domain/chat_models.dart';
import '../../../service/tanglex_service.dart';

class ChatState {
  const ChatState({
    this.loading = true,
    this.messages = const [],
    this.sending = false,
    this.error,
    this.messagingReady = true,
  });

  final bool loading;
  final List<UiMessage> messages;
  final bool sending;
  final String? error;
  final bool messagingReady;

  ChatState copyWith({
    bool? loading,
    List<UiMessage>? messages,
    bool? sending,
    String? error,
    bool clearError = false,
    bool? messagingReady,
  }) =>
      ChatState(
        loading: loading ?? this.loading,
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        error: clearError ? null : (error ?? this.error),
        messagingReady: messagingReady ?? this.messagingReady,
      );
}

class ChatController extends StateNotifier<ChatState> {
  ChatController(this._service, this.chatRef, {required this.isContact})
      : super(const ChatState()) {
    _sub = _service.eventStream.listen(_onEvent);
    refresh();
    if (isContact) _refreshMessagingReady();
  }

  final TanglexService _service;
  final String chatRef;
  final bool isContact;

  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _debounce;

  Future<void> refresh() async {
    if (!_service.isInitialized) return;
    try {
      final raw = await _service.getChatMessages(chatRef, limit: 200);
      final parsed = <UiMessage>[];
      for (final m in raw) {
        final ui = parseChatItem(m);
        if (ui != null) parsed.add(ui);
      }
      // The core returns chronological order already; ensure newest last.
      parsed.sort(
        (a, b) =>
            (a.time ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          b.time ?? DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        messages: parsed,
        clearError: true,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> _refreshMessagingReady() async {
    final ready = await _service.getContactMessagingReady(chatRef);
    if (!mounted || ready == null) return;
    state = state.copyWith(messagingReady: ready);
  }

  void _onEvent(Map<String, dynamic> event) {
    final result = event['result'];
    if (result is! Map) return;
    final type = result['type'] as String?;
    if (type == null) return;

    switch (type) {
      case 'chatItem':
      case 'chatItemNew':
      case 'newChatItems':
      case 'chatItemUpdated':
      case 'chatItemsDeleted':
      case 'groupChatItemsDeleted':
      case 'chatItemsStatusesUpdated':
        _scheduleRefresh();
        break;
      case 'contactSndReady':
      case 'contact':
        if (isContact) _refreshMessagingReady();
        break;
    }
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), refresh);
  }

  Future<bool> sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    state = state.copyWith(sending: true, clearError: true);
    final result = await _service.sendMessage(chatRef, trimmed);
    if (!mounted) return result.ok;
    if (!result.ok) {
      state = state.copyWith(
        sending: false,
        error: result.errorType ?? 'send_failed',
      );
      return false;
    }
    state = state.copyWith(sending: false, clearError: true);
    // The core will emit a chatItemNew event; the listener will refresh.
    return true;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

/// Parameters for the chat controller family.
class ChatArgs {
  const ChatArgs({required this.chatRef, required this.isContact});
  final String chatRef;
  final bool isContact;

  @override
  bool operator ==(Object other) =>
      other is ChatArgs &&
      other.chatRef == chatRef &&
      other.isContact == isContact;

  @override
  int get hashCode => Object.hash(chatRef, isContact);
}

final chatControllerProvider = StateNotifierProvider.autoDispose
    .family<ChatController, ChatState, ChatArgs>((ref, args) {
  final service = ref.watch(tanglexServiceProvider);
  return ChatController(
    service,
    args.chatRef,
    isContact: args.isContact,
  );
});
