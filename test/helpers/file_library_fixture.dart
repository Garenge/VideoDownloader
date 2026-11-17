import 'dart:async';

import 'package:videodownloader/source_parser/download_history_store.dart';
import 'package:videodownloader/source_parser/downloaded_file_store.dart';

class FileLibraryFixture extends DownloadedFileStore {
  FileLibraryFixture()
    : super(directories: () async => [], activePaths: () => {});

  final files = [
    DownloadedFile('/downloads/post-10.mp4', 10, DateTime(2026, 11, 17)),
    DownloadedFile('/downloads/post-2.mp4', 30, DateTime(2026, 11, 16)),
    DownloadedFile('/downloads/post-1.jpg', 20, DateTime(2026, 11, 15)),
  ];
  int scans = 0;
  bool fail = false;
  Completer<List<DownloadedFile>>? pending;

  @override
  Future<List<DownloadedFile>> scan() async {
    scans++;
    if (fail) throw StateError('无法读取目录');
    return pending?.future ?? List.of(files);
  }
}

class EmptyLibraryHistory extends DownloadHistoryStore {
  @override
  Future<List<DownloadHistoryRecord>> load() async => [];
}
