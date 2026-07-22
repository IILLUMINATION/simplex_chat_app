// TangleX — chats list controller.
//
// Owns the `List<ChatPreview>` shown on the Chats screen. Listens to the
// TanglexService event stream and refreshes whenever an event that can affect
// the chats list arrives (HANDOFF.md § 6). Refreshes are debounced ~250 ms so
// bursts of events from `/_start` don't hammer the FFI.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart';
import '../../../providers/persistent_store.dart';
import '../../../service/tanglex_service.dart';

/// State for the chats screen.
class ChatsState {
  const ChatsState({
    this.loading = true,
    this.chats = const [],
    this.error,
  });

  final bool loading;
  final List<ChatPreview> chats;
  final String? error;

  ChatsState copyWith({
    bool? loading,
    List<ChatPreview>? chats,
    String? error,
    bool clearError = false,
  }) =>
      ChatsState(
        loading: loading ?? this.loading,
        chats: chats ?? this.chats,
        error: clearError ? null : (error ?? this.error),
      );
}

class ChatsController extends StateNotifier<ChatsState> {
  ChatsController(this._service) : super(const ChatsState()) {
    _eventSub = _service.eventStream.listen(_onEvent);
    refresh();
  }

  final TanglexService _service;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  Timer? _debounce;

  /// Events whose arrival should re-fetch the chats list.
  static const _refreshTriggers = <String>{
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
    'groupChatItemsDeleted',
    'chatItemsStatusesUpdated',
  };

  void _onEvent(Map<String, dynamic> event) {
    final result = event['result'];
    if (result is! Map) return;
    final type = result['type'] as String?;
    if (type == null) return;
    if (!_refreshTriggers.contains(type)) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), refresh);
  }

  Future<void> refresh() async {
    if (!_service.isInitialized) return;
    try {
      final chats = await _service.getChats(limit: 100);
      if (!mounted) return;
      // Filter out the "contactConnection" placeholders that have no display
      // name yet — they would render as blank rows.
      final visible = chats.where((c) {
        if (c.chatType == 'contactConnection' && c.displayName.isEmpty) {
          return false;
        }
        return true;
      }).toList()
        ..sort((a, b) =>
            (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));
      state = state.copyWith(
        loading: false,
        chats: visible,
        clearError: true,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }
}

final chatsControllerProvider =
    StateNotifierProvider.autoDispose<ChatsController, ChatsState>((ref) {
  final service = ref.watch(tanglexServiceProvider);
  return ChatsController(service);
});
