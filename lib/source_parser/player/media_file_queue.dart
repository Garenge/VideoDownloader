import '../downloaded_file_store.dart';

/// A snapshot keeps previews in the same order as the list that opened them.
class MediaFileQueue {
  MediaFileQueue(DownloadedFile initial, List<DownloadedFile> files)
    : files = List.unmodifiable(
        files.any((file) => file.path == initial.path) ? files : [initial],
      ) {
    index = this.files.indexWhere((file) => file.path == initial.path);
  }

  final List<DownloadedFile> files;
  late int index;
  DownloadedFile get current => files[index];
  String get positionLabel => '${index + 1} / ${files.length}';

  bool move(int offset) {
    final target = index + offset;
    if (target < 0 || target >= files.length) return false;
    index = target;
    return true;
  }
}
