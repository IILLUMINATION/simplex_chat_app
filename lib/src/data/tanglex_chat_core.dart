import '../providers/persistent_store.dart';
import '../service/tanglex_service.dart';
import 'account_models.dart';
import 'chat_core.dart';
import 'connect_plan.dart';
import 'formatted_text.dart';

/// Adapts [TanglexService] (which also has a richer, legacy-facing surface)
/// to the narrow [ChatCore] interface used by the new shell.
class TanglexChatCore implements ChatCore {
  TanglexChatCore(this._service);

  final TanglexService _service;

  @override
  bool get isInitialized => _service.isInitialized;

  @override
  Future<void> initialize() => _service.initialize();

  @override
  Stream<Map<String, dynamic>> get eventStream => _service.eventStream;

  @override
  Future<List<ChatPreview>> getChats({int limit = 50}) =>
      _service.getChats(limit: limit);

  @override
  Future<List<Map<String, dynamic>>> getChatMessages(
    String chatRef, {
    int limit = 50,
  }) => _service.getChatMessages(chatRef, limit: limit);

  @override
  Future<bool> sendMessage(
    String chatRef,
    String text, {
    int? quotedItemId,
  }) async {
    final result = await _service.sendMessage(
      chatRef,
      text,
      quotedItemId: quotedItemId,
    );
    return result.ok;
  }

  @override
  Future<List<MessageSpan>?> parseMarkdown(String text) =>
      _service.parseMarkdown(text);

  @override
  Future<bool> editMessage(String chatRef, int itemId, String text) =>
      _service.editMessage(chatRef, itemId, text);

  @override
  Future<bool> deleteMessage(
    String chatRef,
    int itemId, {
    required bool forEveryone,
  }) => _service.deleteMessage(chatRef, itemId, forEveryone: forEveryone);

  @override
  Future<bool> forwardMessages(
    String toChatRef,
    String fromChatRef,
    List<int> itemIds,
  ) => _service.forwardMessages(toChatRef, fromChatRef, itemIds);

  @override
  Future<bool> sendImages(
    String chatRef,
    List<OutgoingImage> images, {
    String text = '',
    int? quotedItemId,
  }) => _service.sendImages(
    chatRef,
    [
      for (final image in images)
        ImagePayload(
          filePath: image.filePath,
          previewBytes: image.previewBytes,
          previewMime: image.previewMime,
        ),
    ],
    text: text,
    quotedItemId: quotedItemId,
  );

  @override
  Future<bool> sendFile(
    String chatRef,
    String filePath, {
    String text = '',
    int? quotedItemId,
  }) async {
    final result = await _service.sendFile(
      chatRef: chatRef,
      filePath: filePath,
      text: text,
      quotedItemId: quotedItemId,
    );
    return result.ok;
  }

  @override
  Future<bool> receiveFile(int fileId) => _service.receiveFile(fileId);

  @override
  Future<bool> setReaction(
    String chatRef,
    int itemId,
    String emoji, {
    required bool add,
  }) => _service.setReaction(chatRef, itemId, emoji, add: add);

  @override
  Future<bool> acceptContactRequest(int requestId, {bool incognito = false}) =>
      _service.acceptContactRequest(requestId, incognito: incognito);

  @override
  Future<bool> rejectContactRequest(int requestId) =>
      _service.rejectContactRequest(requestId);

  @override
  Future<void> markRead(String chatRef) async {
    await _service.sendCommand('/_read chat $chatRef');
  }

  @override
  Future<AccountsState> getAccounts() async {
    final users = await _service.getUsers();
    final active = await _service.getUser();
    final activeId = active?['userId'] as int?;
    return AccountsState(
      accounts: [
        for (final user in users)
          AccountProfile.fromUserJson(user, activeUserId: activeId),
      ],
      activeUserId: activeId,
    );
  }

  @override
  Future<bool> setActiveUser(int userId) => _service.setActiveUser(userId);

  @override
  Future<AccountProfile?> createProfile({
    required String displayName,
    String fullName = '',
    String? shortDescr,
  }) async {
    final result = await _service.createUserProfile(
      displayName: displayName,
      fullName: fullName,
      shortDescr: shortDescr,
    );
    final user = result?['user'];
    if (user is! Map) return null;
    return AccountProfile.fromUserJson(
      Map<String, dynamic>.from(user),
      activeUserId: user['userId'] as int?,
    );
  }

  @override
  Future<bool> updateProfile(
    int userId, {
    required String displayName,
    String fullName = '',
    String? shortDescr,
    String? image,
  }) => _service.updateUserProfile(
    userId: userId,
    displayName: displayName,
    fullName: fullName,
    shortDescr: shortDescr,
    image: image,
  );

  @override
  Future<String?> getAddress() => _service.createConnectionLink();

  @override
  Future<ConnectOutcome> connectViaLink(String link) =>
      _service.connectViaLink(link);

  @override
  Future<bool> setChatMuted(
    String chatRef, {
    required bool muted,
    required bool pinned,
  }) => _service.setChatSettings(chatRef, muted: muted, pinned: pinned);
}
