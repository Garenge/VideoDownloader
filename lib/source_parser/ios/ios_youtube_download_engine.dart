import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../download_engines/download_engine.dart';
import '../download_queue_controller.dart'
    show DownloadTask, DownloadException, DownloadCanceledException;
import '../download_settings.dart';
import 'ios_download_operation.dart';
import 'youtube_media_download.dart';
import 'ios_media_bridge.dart';
import 'ios_youtube_stream_plan.dart';

class IosYouTubeDownloadEngine extends DownloadEngine {
  const IosYouTubeDownloadEngine({required this.client});

  final http.Client client;

  @override
  Future<File> download({
    required DownloadTask task,
    required Directory directory,
    required DownloadSettings settings,
    required ProcessRunner processRunner,
    required ProcessStarter processStarter,
    required CancelCheck isCancelRequested,
    required void Function() onProgressUpdated,
  }) async {
    final operation = IosDownloadOperation(
      task: task,
      isCanceled: isCancelRequested,
      onProgress: onProgressUpdated,
    );
    final transport = YoutubeHttpClient(BorrowedHttpClient(client));
    final yt = YoutubeExplode(httpClient: transport);
    final workspace = Directory(
      '${directory.path}/.videodownloader_ios/${task.id}',
    );
    await workspace.create(recursive: true);
    File? output;
    var completed = false;
    try {
      task.statusDetail = 'YouTube：应用内解析视频…';
      onProgressUpdated();
      final id = task.resource.youtubeVideoId!;
      final manifest = await _manifest(yt, id, operation);
      final plan = IosYouTubeStreamPlan.select(manifest);
      task.totalBytes = plan.totalBytes;
      task.fileName = 'YouTube-$id-${task.id}.mp4';
      task.addLog(
        'ios_youtube_download_engine.dart#download: '
        'video=${plan.video.tag} audio=${plan.audio?.tag} bytes=${plan.totalBytes}',
      );
      task.statusDetail = 'YouTube：下载视频…';
      onProgressUpdated();
      final video = await YoutubeMediaDownload.save(
        transport: transport,
        youtube: yt,
        info: plan.video,
        workspace: workspace,
        operation: operation,
      );
      final audioInfo = plan.audio;
      if (audioInfo != null) {
        task.statusDetail = 'YouTube：下载音频…';
        onProgressUpdated();
        final audio = await YoutubeMediaDownload.save(
          transport: transport,
          youtube: yt,
          info: audioInfo,
          workspace: workspace,
          operation: operation,
          completedBytes: plan.video.size.totalBytes,
        );
        operation.checkCanceled();
        task.statusDetail = 'YouTube：在 iPhone 上合并音视频…';
        onProgressUpdated();
        output = File('${directory.path}/${task.fileName}');
        await const IosMediaBridge().merge(
          id: task.id,
          videoPath: video.path,
          audioPath: audio.path,
          outputPath: output.path,
          isCanceled: isCancelRequested,
        );
      } else {
        operation.checkCanceled();
        output = await video.rename('${directory.path}/${task.fileName}');
      }
      operation.checkCanceled();
      task.filePath = output.path;
      completed = true;
      return output;
    } on Object catch (error) {
      if (output != null && await output.exists()) await output.delete();
      if (isCancelRequested()) throw const DownloadCanceledException();
      if (error is DownloadException) rethrow;
      throw DownloadException('YouTube 应用内下载失败：$error');
    } finally {
      yt.close();
      if (completed || isCancelRequested()) {
        await workspace.delete(recursive: true);
      }
    }
  }

  Future<StreamManifest> _manifest(
    YoutubeExplode yt,
    String id,
    IosDownloadOperation operation,
  ) async {
    Object? lastError;
    for (final clients in [
      [YoutubeApiClient.ios, YoutubeApiClient.safari],
      [YoutubeApiClient.android, YoutubeApiClient.ios],
      [YoutubeApiClient.mweb, YoutubeApiClient.ios],
    ]) {
      operation.checkCanceled();
      try {
        final result = await operation.wait(
          yt.videos.streamsClient
              .getManifest(id, ytClients: clients)
              .timeout(const Duration(seconds: 30)),
        );
        if (result.streams.isNotEmpty) return result;
      } on DownloadCanceledException {
        rethrow;
      } on Object catch (error) {
        lastError = error;
      }
    }
    throw DownloadException('无法获取 YouTube 视频流，可能需要登录或受访问限制：$lastError');
  }
}
