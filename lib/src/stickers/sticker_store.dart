import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

class StickerItem {
  final String id;
  final String filePath;
  final bool animated;

  StickerItem({
    required this.id,
    required this.filePath,
    required this.animated,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'animated': animated,
      };

  static StickerItem fromJson(Map<String, dynamic> json) {
    return StickerItem(
      id: json['id'] as String,
      filePath: json['filePath'] as String,
      animated: json['animated'] as bool? ?? false,
    );
  }
}

class StickerPack {
  final String id;
  final String name;
  final String? author;
  final String? coverPath;
  final List<StickerItem> stickers;

  StickerPack({
    required this.id,
    required this.name,
    required this.stickers,
    this.author,
    this.coverPath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'author': author,
        'coverPath': coverPath,
        'stickers': stickers.map((s) => s.toJson()).toList(),
      };

  static StickerPack fromJson(Map<String, dynamic> json) {
    final list = (json['stickers'] as List? ?? [])
        .whereType<Map>()
        .map((e) => StickerItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return StickerPack(
      id: json['id'] as String,
      name: json['name'] as String,
      author: json['author'] as String?,
      coverPath: json['coverPath'] as String?,
      stickers: list,
    );
  }
}

class StickerStore {
  StickerStore._();

  static final StickerStore instance = StickerStore._();

  final List<StickerPack> _packs = [];

  List<StickerPack> get packs => List.unmodifiable(_packs);

  Future<Directory> _baseDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/stickers');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<File> _indexFile() async {
    final dir = await _baseDir();
    return File('${dir.path}/index.json');
  }

  Future<void> load() async {
    final file = await _indexFile();
    if (!file.existsSync()) return;
    try {
      final raw = jsonDecode(file.readAsStringSync());
      final list = (raw as List)
          .whereType<Map>()
          .map((e) => StickerPack.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _packs
        ..clear()
        ..addAll(list);
    } catch (_) {}
  }

  Future<void> save() async {
    final file = await _indexFile();
    final data = jsonEncode(_packs.map((p) => p.toJson()).toList());
    file.writeAsStringSync(data);
  }

  Future<StickerPack?> importZip(String zipPath) async {
    try {
      final bytes = File(zipPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      final base = await _baseDir();

      String? packId;
      String? packName;
      String? packAuthor;
      String? coverFile;
      final stickers = <StickerItem>[];

      for (final file in archive) {
        if (file.isFile) {
          final name = file.name;
          if (name.endsWith('manifest.json')) {
            final content = utf8.decode(file.content as List<int>);
            final manifest = jsonDecode(content) as Map<String, dynamic>;
            packId = (manifest['packId'] ?? manifest['id'])?.toString();
            packName = (manifest['name'] ?? 'Sticker Pack').toString();
            packAuthor = manifest['author']?.toString();
            coverFile = manifest['cover']?.toString();
            final list = (manifest['stickers'] as List? ?? []);
            for (final item in list) {
              if (item is Map) {
                final id = item['id']?.toString() ?? '';
                final f = item['file']?.toString() ?? '';
                if (id.isNotEmpty && f.isNotEmpty) {
                  // actual file path resolved after extracting
                  stickers.add(StickerItem(
                    id: id,
                    filePath: f,
                    animated: true,
                  ));
                }
              }
            }
          }
        }
      }

      if (packId == null) return null;
      final packDir = Directory('${base.path}/$packId');
      if (!packDir.existsSync()) {
        packDir.createSync(recursive: true);
      }

      for (final file in archive) {
        if (!file.isFile) continue;
        final out = File('${packDir.path}/${file.name}');
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(file.content as List<int>);
      }

      // resolve sticker paths
      final resolved = stickers
          .map((s) {
            final path = '${packDir.path}/${s.filePath}';
            final lower = path.toLowerCase();
            final animated = lower.endsWith('.webm') || lower.endsWith('.webp');
            return StickerItem(
              id: s.id,
              filePath: path,
              animated: animated,
            );
          })
          .toList();

      String? coverPath;
      if (coverFile != null) {
        final c = File('${packDir.path}/$coverFile');
        if (c.existsSync()) {
          coverPath = c.path;
        }
      }
      coverPath ??= resolved.isNotEmpty ? resolved.first.filePath : null;

      final pack = StickerPack(
        id: packId,
        name: packName ?? packId,
        author: packAuthor,
        coverPath: coverPath,
        stickers: resolved,
      );

      _packs.removeWhere((p) => p.id == pack.id);
      _packs.add(pack);
      await save();
      return pack;
    } catch (_) {
      return null;
    }
  }

  Future<StickerPack?> createPack({
    required String packId,
    required String name,
    String? author,
    required List<String> filePaths,
  }) async {
    if (filePaths.isEmpty) return null;
    try {
      final base = await _baseDir();
      final packDir = Directory('${base.path}/$packId');
      if (!packDir.existsSync()) {
        packDir.createSync(recursive: true);
      }
      final stickers = <StickerItem>[];
      int idx = 1;
      for (final path in filePaths) {
        final src = File(path);
        if (!src.existsSync()) continue;
        final ext = path.toLowerCase().endsWith('.webm')
            ? 'webm'
            : (path.toLowerCase().endsWith('.webp') ? 'webp' : 'webp');
        final id = idx.toString().padLeft(2, '0');
        final out = File('${packDir.path}/$id.$ext');
        await src.copy(out.path);
        final animated = ext == 'webm' || ext == 'webp';
        stickers.add(StickerItem(
          id: id,
          filePath: out.path,
          animated: animated,
        ));
        idx++;
      }
      if (stickers.isEmpty) return null;
      final coverPath = stickers.first.filePath;
      final pack = StickerPack(
        id: packId,
        name: name,
        author: author,
        coverPath: coverPath,
        stickers: stickers,
      );
      _packs.removeWhere((p) => p.id == pack.id);
      _packs.add(pack);
      await save();
      final manifest = {
        'packId': pack.id,
        'name': pack.name,
        'author': pack.author,
        'cover': coverPath.split('/').last,
        'stickers': stickers
            .map((s) => {'id': s.id, 'file': s.filePath.split('/').last})
            .toList(),
      };
      File('${packDir.path}/manifest.json')
          .writeAsStringSync(jsonEncode(manifest));
      return pack;
    } catch (_) {
      return null;
    }
  }

  /// Export a sticker pack as a .sxpz zip file. Returns the path to the exported file.
  Future<String?> exportPack({required String packId}) async {
    final pack = _packs.where((p) => p.id == packId).firstOrNull;
    if (pack == null) return null;
    try {
      final packDir = Directory('${(await _baseDir()).path}/$packId');
      if (!packDir.existsSync()) return null;

      final archive = Archive();

      // Add manifest
      final manifest = {
        'packId': pack.id,
        'name': pack.name,
        'author': pack.author,
        'cover': pack.coverPath?.split('/').last ?? '',
        'stickers': pack.stickers
            .map((s) => {'id': s.id, 'file': s.filePath.split('/').last})
            .toList(),
      };
      final manifestBytes = utf8.encode(jsonEncode(manifest));
      archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

      // Add sticker files
      for (final sticker in pack.stickers) {
        final file = File(sticker.filePath);
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          final name = sticker.filePath.split('/').last;
          archive.addFile(ArchiveFile(name, bytes.length, bytes));
        }
      }

      // Create zip
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) return null;

      // Save to Downloads or temp dir
      final outDir = Directory('/storage/emulated/0/Download').existsSync()
          ? Directory('/storage/emulated/0/Download')
          : await getTemporaryDirectory();
      final outPath = '${outDir.path}/$packId.sxpz';
      File(outPath).writeAsBytesSync(zipBytes);
      return outPath;
    } catch (_) {
      return null;
    }
  }
}
