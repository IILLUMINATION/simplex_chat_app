import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart';
import '../../../localization/app_localizations.dart';
import '../../../providers/locale_provider.dart';

import '../../core/theme/tx_theme.dart';
import '../../shared/avatar.dart';
import '../../shared/empty_state.dart';
import '../settings/theme_settings_screen.dart';

final _activeUserProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final service = ref.watch(tanglexServiceProvider);
  if (!service.isInitialized) return null;
  return service.getUser();
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final theme = context.txTheme;
    final user = ref.watch(_activeUserProvider);

    return Scaffold(
      backgroundColor: theme.chatBackground,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_activeUserProvider),
        child: user.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => TxEmptyState(
            icon: Icons.error_outline_rounded,
            title: t.translate('initialization_error'),
            subtitle: err.toString(),
          ),
          data: (data) {
            final profile = data?['profile'] as Map<String, dynamic>?;
            final displayName =
                (profile?['displayName'] as String?)?.trim() ?? '';
            final fullName = (profile?['fullName'] as String?)?.trim() ?? '';
            final descr = (profile?['shortDescr'] as String?)?.trim() ?? '';

            if (profile == null || displayName.isEmpty) {
              return _NoProfileView(ref: ref);
            }

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _TelegramProfileHeader(
                    displayName: displayName,
                    fullName: fullName,
                    ref: ref,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: _InfoGroupCard(
                      shortDescr: descr,
                      ref: ref,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: _SettingsGroupCard(ref: ref),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TelegramProfileHeader extends ConsumerWidget {
  const _TelegramProfileHeader({
    required this.displayName,
    required this.fullName,
    required this.ref,
  });

  final String displayName;
  final String fullName;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final theme = context.txTheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            cs.primaryContainer.withValues(alpha: 0.4),
            theme.chatBackground,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 20),
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.25),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: TxAvatar(name: displayName, size: 100),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Material(
                    color: cs.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: () => _showAvatarPicker(context, ref),
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.camera_alt_rounded,
                          size: 18,
                          color: cs.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              displayName,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
                color: theme.peerBubbleFg,
              ),
            ),
            if (fullName.isNotEmpty && fullName != displayName) ...[
              const SizedBox(height: 2),
              Text(
                fullName,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'SimpleX Active',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _HeaderActionButton(
                      icon: Icons.qr_code_2_rounded,
                      label: 'QR-код',
                      onTap: () => _showQrModal(context, ref),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HeaderActionButton(
                      icon: Icons.edit_outlined,
                      label: 'Изменить',
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => _EditProfileDialog(
                            ref: ref,
                            currentName: displayName,
                            currentFull: fullName,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HeaderActionButton(
                      icon: Icons.palette_outlined,
                      label: 'Оформление',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ThemeSettingsScreen(),
                          ),
                        );
                      },
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

  void _showQrModal(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QrCodeSheet(ref: ref),
    );
  }

  void _showAvatarPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
          Material(
            color: Colors.transparent,
            child: ListTile(
              leading: const Icon(Icons.image_rounded),
              title: const Text('Выбрать аватар (заглушка)'),
              onTap: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Смена аватара через галерею в разработке')),
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

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.txTheme;
    return Material(
      color: theme.peerBubbleBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.peerBubbleFg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoGroupCard extends StatefulWidget {
  const _InfoGroupCard({required this.shortDescr, required this.ref});

  final String shortDescr;
  final WidgetRef ref;

  @override
  State<_InfoGroupCard> createState() => _InfoGroupCardState();
}

class _InfoGroupCardState extends State<_InfoGroupCard> {
  String? _connLink;
  bool _loadingLink = true;

  @override
  void initState() {
    super.initState();
    _fetchLink();
  }

  Future<void> _fetchLink() async {
    try {
      final service = widget.ref.read(tanglexServiceProvider);
      final link = await service.createConnectionLink();
      if (mounted) {
        setState(() {
          _connLink = link;
          _loadingLink = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingLink = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = context.txTheme;

    return Container(
      decoration: BoxDecoration(
        color: theme.peerBubbleBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'ПРИВАТНАЯ ССЫЛКА СВЯЗИ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: cs.primary,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: ListTile(
              leading: Icon(Icons.link_rounded, color: theme.peerBubbleFg),
              title: Text(
                _loadingLink
                    ? 'Генерация ссылки...'
                    : (_connLink ?? 'Не удалось получить ссылку'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.peerBubbleFg,
                ),
              ),
              subtitle: Text(
                'Ссылка для добавления вас в чат SimpleX',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
              trailing: Icon(Icons.copy_rounded, size: 18, color: theme.peerBubbleFg),
              onTap: () {
                if (_connLink != null) {
                  Clipboard.setData(ClipboardData(text: _connLink!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ссылка связи скопирована в буфер обмена')),
                  );
                }
              },
            ),
          ),
          if (widget.shortDescr.isNotEmpty) ...[
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
            Material(
              color: Colors.transparent,
              child: ListTile(
                leading: Icon(Icons.info_outline_rounded, color: theme.peerBubbleFg),
                title: Text(
                  widget.shortDescr,
                  style: TextStyle(color: theme.peerBubbleFg),
                ),
                subtitle: Text(
                  'О себе',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = context.txTheme;
    final localeData = ref.watch(localeNotifierProvider);

    return Container(
      decoration: BoxDecoration(
        color: theme.peerBubbleBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'НАСТРОЙКИ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: cs.primary,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: ListTile(
              leading: Icon(Icons.translate_rounded, color: theme.peerBubbleFg),
              title: Text(
                'Язык',
                style: TextStyle(color: theme.peerBubbleFg),
              ),
              subtitle: Text(
                localeData.locale == 'ru' ? 'Русский' : 'English',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              trailing: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'en', label: Text('EN')),
                  ButtonSegment(value: 'ru', label: Text('RU')),
                ],
                selected: {localeData.locale},
                showSelectedIcon: false,
                onSelectionChanged: (set) {
                  if (set.isNotEmpty) {
                    final locale = AppLocale.fromCode(set.first);
                    ref.read(localeNotifierProvider.notifier).setLocale(locale);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrCodeSheet extends StatefulWidget {
  const _QrCodeSheet({required this.ref});
  final WidgetRef ref;

  @override
  State<_QrCodeSheet> createState() => _QrCodeSheetState();
}

class _QrCodeSheetState extends State<_QrCodeSheet> {
  String? _link;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLink();
  }

  Future<void> _loadLink() async {
    final service = widget.ref.read(tanglexServiceProvider);
    final link = await service.createConnectionLink();
    if (mounted) {
      setState(() {
        _link = link;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Ваша ссылка SimpleX',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Отсканируйте этот QR-код из приложения, чтобы начать приватный чат.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 24),
          if (_loading)
            const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_link == null)
            const Text('Не удалось сгенерировать ссылку')
          else
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: CustomPaint(
                    size: const Size(200, 200),
                    painter: _SimpleQrPainter(_link!),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _link!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ссылка скопирована!')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Копировать ссылку'),
                ),
              ],
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SimpleQrPainter extends CustomPainter {
  _SimpleQrPainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    const gridCount = 21;
    final cellSize = size.width / gridCount;

    final bytes = utf8.encode(data);
    
    _drawSquare(canvas, paint, 0, 0, 7, cellSize);
    _drawSquare(canvas, paint, gridCount - 7, 0, 7, cellSize);
    _drawSquare(canvas, paint, 0, gridCount - 7, 7, cellSize);

    for (int r = 0; r < gridCount; r++) {
      for (int c = 0; c < gridCount; c++) {
        if ((r < 7 && c < 7) ||
            (r < 7 && c >= gridCount - 7) ||
            (r >= gridCount - 7 && c < 7)) {
          continue;
        }
        final index = (r * gridCount + c) % bytes.length;
        if ((bytes[index] + r + c) % 2 == 0) {
          canvas.drawRect(
            Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize),
            paint,
          );
        }
      }
    }
  }

  void _drawSquare(Canvas canvas, Paint paint, int x, int y, int size, double cellSize) {
    for (int r = 0; r < size; r++) {
      for (int c = 0; c < size; c++) {
        if (r == 0 || r == size - 1 || c == 0 || c == size - 1 || (r >= 2 && r <= 4 && c >= 2 && c <= 4)) {
          canvas.drawRect(
            Rect.fromLTWH((x + c) * cellSize, (y + r) * cellSize, cellSize, cellSize),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({
    required this.ref,
    required this.currentName,
    required this.currentFull,
  });

  final WidgetRef ref;
  final String currentName;
  final String currentFull;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _fullCtrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.currentName);
    _fullCtrl = TextEditingController(text: widget.currentFull);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _fullCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Редактировать профиль'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _fullCtrl,
            decoration: const InputDecoration(labelText: 'Полное имя / Фамилия'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _loading
              ? null
              : () async {
                  setState(() => _loading = true);
                  final service = widget.ref.read(tanglexServiceProvider);
                  await service.createUserProfile(
                    displayName: _nameCtrl.text.trim(),
                    fullName: _fullCtrl.text.trim(),
                  );
                  if (!mounted) return;
                  widget.ref.invalidate(_activeUserProvider);
                  if (!mounted) return;
                  // ignore: use_build_context_synchronously
                  Navigator.pop(context);
                },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _NoProfileView extends StatelessWidget {
  const _NoProfileView({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const TxEmptyState(
            icon: Icons.person_outline_rounded,
            title: 'Профиль не создан',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => _EditProfileDialog(
                  ref: ref,
                  currentName: 'TangleX User',
                  currentFull: '',
                ),
              );
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Создать профиль'),
          ),
        ],
      ),
    );
  }
}
