import 'dart:io';

import '../download_queue_controller.dart' show DownloadTask;
import '../download_settings.dart';

typedef CancelCheck = bool Function();
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef ProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

abstract class DownloadEngine {
  const DownloadEngine();

  Future<File> download({
    required DownloadTask task,
    required Directory directory,
    required DownloadSettings settings,
    required ProcessRunner processRunner,
    required ProcessStarter processStarter,
    required CancelCheck isCancelRequested,
    required void Function() onProgressUpdated,
  });
}

