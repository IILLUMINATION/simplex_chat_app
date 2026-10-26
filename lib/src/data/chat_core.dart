import '../providers/persistent_store.dart';
import 'account_models.dart';
import 'connect_plan.dart';

/// The subset of the core API the UI needs. Implemented by `TanglexService`
/// in production and by an in-memory fake in tests.
abstract class ChatCore {
  bool get isInitialized;

  Future<void> initialize();

  Stream<Map<String, dynamic>> get eventStream;

  Future<List<ChatPreview>> getChats({int limit});

  Future<List<Map<String, dynamic>>> getChatMessages(
    String chatRef, {
    int limit,
  });

  Future<bool> sendMessage(String chatRef, String text, {int? quotedItemId});

  /// Clears the unread counter for [chatRef].
  Future<void> markRead(String chatRef);

  /// Local SimpleX users (profiles) and the active one.
  Future<AccountsState> getAccounts();

  Future<bool> setActiveUser(int userId);

  Future<AccountProfile?> createProfile({
    required String displayName,
    String fullName,
    String? shortDescr,
  });

  Future<bool> updateProfile(
    int userId, {
    required String displayName,
    String fullName,
    String? shortDescr,
  });

  /// Returns the profile's SimpleX address link, creating one if needed.
  Future<String?> getAddress();

  /// Resolves a SimpleX link (full or short) or name, then connects.
  Future<ConnectOutcome> connectViaLink(String link);

  Future<bool> setChatMuted(
    String chatRef, {
    required bool muted,
    required bool pinned,
  });
}
