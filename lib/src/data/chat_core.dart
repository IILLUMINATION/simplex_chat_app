import 'dart:typed_data';

import '../providers/persistent_store.dart';
import 'account_models.dart';
import 'connect_plan.dart';
import 'formatted_text.dart';

/// One outgoing photo: the full-size file plus a small inline preview.
class OutgoingImage {
  const OutgoingImage({
    required this.filePath,
    required this.previewBytes,
    required this.previewMime,
  });

  final String filePath;
  final Uint8List previewBytes;
  final String previewMime;
}

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

  /// Runs the core's own markdown parser (`chat_parse_markdown`) so an
  /// outgoing bubble can be painted before the timeline refetch delivers the
  /// chat item. Returns null when the text has no formatting.
  Future<List<MessageSpan>?> parseMarkdown(String text);

  /// Replaces the text of a sent chat item (`/_update item`, the official
  /// clients call it `apiUpdateChatItem`).
  Future<bool> editMessage(String chatRef, int itemId, String text);

  /// Removes the chat item (`/_delete item`). [forEveryone] maps to the core's
  /// `broadcast` mode; `internal` deletes only the local copy and is the only
  /// option once `CIMeta.deletable` turns false.
  Future<bool> deleteMessage(
    String chatRef,
    int itemId, {
    required bool forEveryone,
  });

  /// Forwards [itemIds] from [fromChatRef] into [toChatRef] (`/_forward`).
  /// The core copies the content and stamps `forwardedBy`, exactly like the
  /// official clients' "Forward" action (`Commands.hs:5470`).
  Future<bool> forwardMessages(
    String toChatRef,
    String fromChatRef,
    List<int> itemIds,
  );

  /// Sends [images] as one album. [text] is the album caption and travels on
  /// the first image, which is where SimpleX renders `msgContent.text` for a
  /// photo (`MCText` next to `MCImage`).
  Future<bool> sendImages(
    String chatRef,
    List<OutgoingImage> images, {
    String text = '',
    int? quotedItemId,
  });

  Future<bool> sendFile(
    String chatRef,
    String filePath, {
    String text = '',
    int? quotedItemId,
  });

  /// Accepts an incoming file transfer (`/freceive`); official clients do this
  /// automatically for small images (`SimpleXAPI.kt:2930`).
  Future<bool> receiveFile(int fileId);

  /// Adds or removes [emoji] on the chat item; returns false on a core error.
  Future<bool> setReaction(
    String chatRef,
    int itemId,
    String emoji, {
    required bool add,
  });

  /// Accepts an incoming contact request (`/_accept`).
  Future<bool> acceptContactRequest(int requestId, {bool incognito = false});

  /// Rejects an incoming contact request (`/_reject`).
  Future<bool> rejectContactRequest(int requestId);

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
    String? image,
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
