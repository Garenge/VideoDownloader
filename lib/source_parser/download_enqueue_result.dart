import 'download_queue_controller.dart';

enum DownloadEnqueueAction {
  created,
  retried,
  existing,
  downloaded,
  unavailable,
}

class DownloadEnqueueResult {
  const DownloadEnqueueResult(this.action, [this.task]);

  final DownloadEnqueueAction action;
  final DownloadTask? task;

  bool get queued =>
      action == DownloadEnqueueAction.created ||
      action == DownloadEnqueueAction.retried;
}
