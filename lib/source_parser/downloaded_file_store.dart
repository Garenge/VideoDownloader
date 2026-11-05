import 'dart:io';

class DownloadedFile {
  const DownloadedFile(this.path, this.size, this.modified);
  final String path;
  final int size;
  final DateTime modified;
  String get name => Uri.file(path).pathSegments.last;
  String get extension =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
  bool get isImage =>
      const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'}.contains(extension);
  bool get isVideo =>
      const {'mp4', 'mov', 'm4v', 'mkv', 'webm', 'avi'}.contains(extension);
}

/// Reads actual files independently of the capped download history.
class DownloadedFileStore {
  DownloadedFileStore({required this.directories, required this.activePaths});
  final Future<List<Directory>> Function() directories;
  final Set<String> Function() activePaths;

  Future<List<DownloadedFile>> scan() async {
    final found = <String, DownloadedFile>{};
    for (final directory in await _roots()) {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || _isTemporary(entity)) continue;
        if (activePaths().contains(entity.path)) continue;
        try {
          final stat = await entity.stat();
          if (stat.type == FileSystemEntityType.file) {
            found[entity.path] = DownloadedFile(
              entity.path,
              stat.size,
              stat.modified,
            );
          }
        } on FileSystemException {
          // A file can disappear while another app is managing the directory.
        }
      }
    }
    return found.values.toList()
      ..sort((a, b) => b.modified.compareTo(a.modified));
  }

  Future<List<Directory>> _roots() async {
    final roots = <String, Directory>{};
    for (final directory in await directories()) {
      if (await directory.exists()) {
        final path = await directory.resolveSymbolicLinks();
        roots[path] = directory.absolute;
      }
    }
    return roots.values.toList();
  }

  bool _isTemporary(File file) {
    final name = Uri.file(file.path).pathSegments.last.toLowerCase();
    return name.startsWith('.') ||
        name.endsWith('.part') ||
        name.endsWith('.tmp') ||
        name.endsWith('.ytdl');
  }

  Future<void> delete(DownloadedFile entry) async {
    final file = File(entry.path);
    if (!await file.exists()) return;
    final path = await file.resolveSymbolicLinks();
    var allowed = false;
    for (final root in await _roots()) {
      final rootPath = await root.resolveSymbolicLinks();
      if (path.startsWith('$rootPath${Platform.pathSeparator}')) allowed = true;
    }
    if (!allowed || activePaths().contains(entry.path)) {
      throw const FileSystemException('该文件不在下载目录中，或仍在下载');
    }
    await file.delete();
  }
}
