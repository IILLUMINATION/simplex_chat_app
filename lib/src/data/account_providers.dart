import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_models.dart';
import 'chat_providers.dart';
import 'connect_plan.dart';

/// Local profiles and the active one. Refreshes when the core announces a
/// profile switch or an edit.
final accountsProvider =
    AsyncNotifierProvider<AccountsNotifier, AccountsState>(AccountsNotifier.new);

class AccountsNotifier extends AsyncNotifier<AccountsState> {
  Timer? _debounce;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _disposed = false;

  @override
  Future<AccountsState> build() async {
    final core = ref.watch(chatCoreProvider);
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
      _sub?.cancel();
    });
    await ref.watch(coreReadyProvider.future);
    _sub = core.eventStream.listen((event) {
      final type = switch (coreEventType(event)) {
        'activeUser' || 'userProfileUpdated' => true,
        _ => false,
      };
      if (!type) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 150), refresh);
    });
    return core.getAccounts();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    try {
      final accounts = await ref.read(chatCoreProvider).getAccounts();
      if (_disposed) return;
      state = AsyncData(accounts);
    } catch (error, stack) {
      if (_disposed) return;
      if (state.valueOrNull == null) state = AsyncError(error, stack);
    }
  }

  Future<bool> switchTo(int userId) async {
    final ok = await ref.read(chatCoreProvider).setActiveUser(userId);
    if (!ok) return false;
    await refresh();
    await ref.read(chatsProvider.notifier).refresh();
    return true;
  }

  Future<AccountProfile?> create({
    required String displayName,
    String fullName = '',
    String? shortDescr,
  }) async {
    final account = await ref
        .read(chatCoreProvider)
        .createProfile(
          displayName: displayName,
          fullName: fullName,
          shortDescr: shortDescr,
        );
    if (account == null) return null;
    await refresh();
    await ref.read(chatsProvider.notifier).refresh();
    return account;
  }

  Future<bool> updateProfile(
    int userId, {
    required String displayName,
    String fullName = '',
    String? shortDescr,
    String? image,
  }) async {
    final ok = await ref
        .read(chatCoreProvider)
        .updateProfile(
          userId,
          displayName: displayName,
          fullName: fullName,
          shortDescr: shortDescr,
          image: image,
        );
    if (ok) await refresh();
    return ok;
  }

  Future<String?> getAddress() => ref.read(chatCoreProvider).getAddress();

  Future<ConnectOutcome> connectViaLink(String link) async {
    final outcome = await ref.read(chatCoreProvider).connectViaLink(link);
    if (outcome.ok) await ref.read(chatsProvider.notifier).refresh();
    return outcome;
  }
}
