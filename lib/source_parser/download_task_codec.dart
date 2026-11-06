import 'download_queue_controller.dart';
import 'source_resource.dart';

/// Only durable state belongs here; transient connections and logs are rebuilt.
class DownloadTaskCodec {
  static Map<String, Object?> encode(DownloadTask task) => {
    'id': task.id,
    'fileName': task.fileName,
    'status': task.status.name,
    'progress': task.progress,
    'receivedBytes': task.receivedBytes,
    'totalBytes': task.totalBytes,
    'filePath': task.filePath,
    'directoryPath': task.directoryPath,
    'errorMessage': task.errorMessage,
    'resource': _encodeResource(task.resource),
  };

  static Map<String, Object?> _encodeResource(SourceResource resource) => {
    'title': resource.title,
    'url': resource.url,
    'type': resource.type.name,
    'platform': resource.platform.name,
    'host': resource.host,
    'sizeHint': resource.sizeHint,
    'youtubeVideoId': resource.youtubeVideoId,
    'requiresYtDlp': resource.requiresYtDlp,
  };

  static DownloadTask? decode(Object? value) {
    try {
      final json = value as Map<String, dynamic>;
      final task = DownloadTask(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        resource: _decodeResource(json['resource'] as Map<String, dynamic>),
      );
      _restoreState(task, json);
      return task;
    } on Object {
      return null;
    }
  }

  static SourceResource _decodeResource(Map<String, dynamic> json) =>
      SourceResource(
        title: json['title'] as String,
        url: json['url'] as String,
        type: SourceResourceType.values.byName(json['type'] as String),
        platform: SourcePlatform.values.byName(json['platform'] as String),
        host: json['host'] as String,
        sizeHint: json['sizeHint'] as String,
        youtubeVideoId: json['youtubeVideoId'] as String?,
        requiresYtDlp: json['requiresYtDlp'] as bool? ?? false,
      );

  static void _restoreState(DownloadTask task, Map<String, dynamic> json) {
    task.status = DownloadStatus.values.byName(json['status'] as String);
    if (task.status == DownloadStatus.downloading) {
      task.status = DownloadStatus.pending;
    }
    task.progress = (json['progress'] as num).toDouble().clamp(0, 1);
    task.receivedBytes = json['receivedBytes'] as int;
    task.totalBytes = json['totalBytes'] as int?;
    task.filePath = json['filePath'] as String?;
    task.directoryPath = json['directoryPath'] as String?;
    task.errorMessage = json['errorMessage'] as String?;
  }
}
