import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_providers.dart';
import '../data/chat_providers.dart';
import '../design/app_theme.dart';
import 'models.dart';
import 'widgets/peer_avatar.dart';

/// Telegram-style "Contacts" page: every direct chat under the active profile.
class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key, required this.onOpenChat});

  final ValueChanged<String> onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    final m = theme.metrics;
    final chats = ref.watch(chatsProvider).valueOrNull ?? const <ChatSummary>[];
    final contacts = chats.where((c) => !c.isGroup).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      backgroundColor: p.windowBg,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: m.topBarHeight,
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  _IconAction(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Contacts',
                      style: t.chatTitle.copyWith(color: p.text),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      '${contacts.length}',
                      style: t.listTime.copyWith(color: p.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: p.divider),
            Expanded(
              child: contacts.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 44,
                              color: p.icon,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No contacts yet',
                              style: t.listName.copyWith(color: p.text),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Use New chat to connect with a SimpleX link.',
                              textAlign: TextAlign.center,
                              style: t.listPreview.copyWith(
                                color: p.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: contacts.length,
                      itemBuilder: (context, index) {
                        final contact = contacts[index];
                        return _ContactRow(
                          contact: contact,
                          onTap: () {
                            final navigator = Navigator.of(context);
                            navigator.pop();
                            onOpenChat(contact.id);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.contact, required this.onTap});

  final ChatSummary contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;
    final m = theme.metrics;
    return InkWell(
      onTap: onTap,
      hoverColor: p.listRowHover,
      child: SizedBox(
        height: m.listRowHeight,
        child: Padding(
          padding: m.listPadding,
          child: Row(
            children: [
              PeerAvatar(
                seed: contact.id,
                title: contact.name,
                size: m.avatarSize,
                imageBytes: contact.avatarBytes,
              ),
              SizedBox(width: m.avatarTextGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      contact.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.listName.copyWith(color: p.listName),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      contact.canSend ? 'connected' : 'connection pending…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.listPreview.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: p.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      hoverColor: theme.palette.windowBgOver,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          icon,
          size: theme.metrics.iconSize,
          color: theme.palette.icon,
        ),
      ),
    );
  }
}

/// Telegram-style "New chat": pick an existing contact or connect by link.
Future<void> showNewChatDialog(
  BuildContext context, {
  required List<ChatSummary> contacts,
  required ValueChanged<String> onOpenChat,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x66000000),
    builder: (_) =>
        _NewChatDialog(contacts: contacts, onOpenChat: onOpenChat),
  );
}

class _NewChatDialog extends ConsumerStatefulWidget {
  const _NewChatDialog({required this.contacts, required this.onOpenChat});

  final List<ChatSummary> contacts;
  final ValueChanged<String> onOpenChat;

  @override
  ConsumerState<_NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends ConsumerState<_NewChatDialog> {
  final _link = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final link = _link.text.trim();
    if (link.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await ref
        .read(accountsProvider.notifier)
        .connectViaLink(link);
    if (!mounted) return;
    if (!outcome.ok) {
      setState(() {
        _busy = false;
        _error = outcome.message ??
            'Could not connect. Check the link and try again.';
      });
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Connection request sent'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openContact(ChatSummary contact) {
    final navigator = Navigator.of(context);
    navigator.pop();
    widget.onOpenChat(contact.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final p = theme.palette;
    final t = theme.typography;

    return Dialog(
      backgroundColor: p.windowBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New chat', style: t.chatTitle.copyWith(color: p.text)),
              const SizedBox(height: 4),
              Text(
                'Pick a contact, or paste a SimpleX link or name.',
                style: t.listPreview.copyWith(color: p.textSecondary),
              ),
              if (widget.contacts.isNotEmpty) ...[
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.contacts.length,
                    itemBuilder: (context, index) {
                      final contact = widget.contacts[index];
                      return InkWell(
                        onTap: () => _openContact(contact),
                        hoverColor: p.windowBgOver,
                        child: SizedBox(
                          height: 44,
                          child: Row(
                            children: [
                              PeerAvatar(
                                seed: contact.id,
                                title: contact.name,
                                size: 30,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  contact.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.listPreview.copyWith(color: p.text),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: p.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Container(height: 1, color: p.divider),
              const SizedBox(height: 14),
              TextField(
                controller: _link,
                enabled: !_busy,
                onSubmitted: (_) => _connect(),
                style: t.input.copyWith(color: p.text),
                cursorColor: p.accent,
                decoration: InputDecoration(
                  labelText: 'SimpleX link or name',
                  hintText: 'https://…/c#… or @name',
                  labelStyle: t.listPreview.copyWith(color: p.textSecondary),
                  hintStyle: t.input.copyWith(color: p.searchHint),
                  filled: true,
                  fillColor: p.windowBgOver,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: p.accent),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: t.listTime.copyWith(color: p.error),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    style: TextButton.styleFrom(foregroundColor: p.accent),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _busy ? null : _connect,
                    style: TextButton.styleFrom(foregroundColor: p.accent),
                    child: _busy
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: p.accent,
                            ),
                          )
                        : const Text('Connect'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
