import 'package:flutter/foundation.dart';

import 'downloaded_file_store.dart';

class DownloadedFilesSelection extends ChangeNotifier {
  final Set<String> _paths = {};
  bool selecting = false;
  bool busy = false;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  int get count => _paths.length;
  bool contains(DownloadedFile file) => _paths.contains(file.path);

  List<DownloadedFile> selected(List<DownloadedFile> files) =>
      files.where(contains).toList();

  void enter() {
    selecting = true;
    notifyListeners();
  }

  void toggle(DownloadedFile file) {
    if (busy) return;
    selecting = true;
    if (!_paths.remove(file.path)) _paths.add(file.path);
    notifyListeners();
  }

  void selectAll(List<DownloadedFile> files) {
    _paths
      ..clear()
      ..addAll(files.map((file) => file.path));
    notifyListeners();
  }

  void retain(Iterable<DownloadedFile> files) {
    _paths.retainAll(files.map((file) => file.path));
    notifyListeners();
  }

  void clear({bool exit = false}) {
    _paths.clear();
    if (exit) selecting = false;
    notifyListeners();
  }

  void setBusy(bool value) {
    if (_disposed) return;
    busy = value;
    notifyListeners();
  }
}
