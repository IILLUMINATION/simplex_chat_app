import 'package:flutter/material.dart';

import '../../../../stickers/sticker_store.dart' show StickerPack, StickerItem;
import '../media/media_widgets.dart';

class StickerPickerSheet extends StatefulWidget {
  final List<StickerPack> packs;
  final VoidCallback onImport;
  final VoidCallback onCreate;
  final VoidCallback? onExport;
  final void Function(int index) onPackSelected;
  final void Function(StickerPack pack, StickerItem item) onSend;

  const StickerPickerSheet({
    required this.packs,
    required this.onImport,
    required this.onCreate,
    this.onExport,
    required this.onPackSelected,
    required this.onSend,
  });

  @override
  State<StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<StickerPickerSheet> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final packs = widget.packs;
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.55,
        child: Column(
          children: [
            if (packs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Стикеры не установлены',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: widget.onImport,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Импорт'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: widget.onCreate,
                          icon: const Icon(Icons.add),
                          label: const Text('Создать'),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                height: 54,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: packs.length + 3,
                  itemBuilder: (context, index) {
                    if (index == packs.length) {
                      return IconButton(
                        onPressed: widget.onImport,
                        icon: const Icon(Icons.add),
                      );
                    }
                    if (index == packs.length + 1) {
                      return IconButton(
                        onPressed: widget.onCreate,
                        icon: const Icon(Icons.create),
                      );
                    }
                    if (index == packs.length + 2) {
                      return IconButton(
                        onPressed: widget.onExport,
                        icon: const Icon(Icons.share),
                      );
                    }
                    final p = packs[index];
                    final selected = index == _selected;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selected = index);
                        widget.onPackSelected(index);
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 6,
                        ),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: selected
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: p.coverPath != null
                            ? StickerThumb(filePath: p.coverPath!)
                            : Center(
                                child: Text(
                                  p.name.characters.first,
                                  style: theme.textTheme.labelLarge,
                                ),
                              ),
                      ),
                    );
                  },
                ),
              ),
            const Divider(height: 1),
            if (packs.isNotEmpty)
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: packs[_selected].stickers.length,
                  itemBuilder: (context, index) {
                    final s = packs[_selected].stickers[index];
                    return GestureDetector(
                      onTap: () => widget.onSend(packs[_selected], s),
                      child: StickerThumb(filePath: s.filePath),
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
