import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../download_queue_controller.dart';
import 'ios_download_operation.dart';

/// Keeps formats separate so newly selected streams never reuse different bytes.
class YoutubeMediaDownload {
  static File mediaFile(Directory workspace, StreamInfo info) =>
      File('${workspace.path}/${info.tag}-${info.size.totalBytes}.part');

  static Future<File> save({
    required YoutubeHttpClient transport,
    required YoutubeExplode youtube,
    required StreamInfo info,
    required Directory workspace,
    required IosDownloadOperation operation,
    int completedBytes = 0,
  }) async {
    final file = mediaFile(workspace, info);
    final size = info.size.totalBytes;
    var offset = await file.exists() ? await file.length() : 0;
    if (offset > size || info.fragments.isNotEmpty) offset = 0;
    if (offset == size && size > 0) {
      operation.task.receivedBytes = completedBytes + size;
      operation.onProgress();
      return file;
    }
    if (info is HlsMuxedStreamInfo ||
        info is HlsAudioStreamInfo ||
        info is HlsVideoStreamInfo) {
      throw const DownloadException('此流不支持按字节续传，请选择 MP4 格式');
    }
    await operation.save(
      transport.getStream(
        info,
        start: offset,
        streamClient: youtube.videos.streamsClient,
      ),
      file,
      expectedBytes: size,
      offset: offset,
      completedBytes: completedBytes,
    );
    return file;
  }
}
