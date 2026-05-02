import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../download_queue_controller.dart'
    show DownloadTask, DownloadCanceledException, DownloadException;
import '../download_settings.dart';
import 'download_engine.dart';

/// 在等待 [future] 期间周期性检查 [isCancelRequested]，以便长时间的 await 也能响应取消。
Future<T> _awaitUnlessCanceled<T>(
  Future<T> future,
  CancelCheck isCancelRequested,
) async {
  final wrapper = Completer<T>();
  future.then<void>(
    (value) {
      if (!wrapper.isCompleted) {
        wrapper.complete(value);
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!wrapper.isCompleted) {
        wrapper.completeError(error, stackTrace);
      }
    },
  );

  late final StreamSubscription<void> tickSub;
  tickSub = Stream.periodic(const Duration(milliseconds: 100)).listen((_) {
    if (isCancelRequested() && !wrapper.isCompleted) {
      wrapper.completeError(const DownloadCanceledException());
    }
  });

  try {
    return await wrapper.future;
  } finally {
    await tickSub.cancel();
  }
}

class YouTubeDownloadEngine extends DownloadEngine {
  const YouTubeDownloadEngine({required http.Client httpClient})
    : _client = httpClient;

  final http.Client _client;

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
    final resource = task.resource;
    final videoId = resource.youtubeVideoId;
    if (videoId == null || videoId.trim().isEmpty) {
      throw const DownloadException('YouTube 资源缺少 videoId');
    }

    // Prevent YoutubeExplode.close() from closing the shared queue client.
    final yt = YoutubeExplode(
      httpClient: YoutubeHttpClient(_NonClosingHttpClient(_client)),
    );
    File? outputFile;
    try {
      task.addLog(
        'lib/source_parser/download_engines/youtube_download_engine.dart#download: explode start videoId=$videoId',
      );
      task.statusDetail = 'YouTube：获取视频信息与可用格式…';
      onProgressUpdated();
      final video = await _awaitUnlessCanceled(
        yt.videos.get(videoId),
        isCancelRequested,
      );
      task.statusDetail = 'YouTube：解析可用清晰度…';
      onProgressUpdated();
      final manifest = await _awaitUnlessCanceled(
        _getManifestWithFallback(yt, videoId),
        isCancelRequested,
      );
      final streamInfo = _pickYoutubeStreamInfo(manifest);
      if (streamInfo == null) {
        throw const DownloadException('未找到可下载的流（可能受地区/年龄限制）');
      }
      task.addLog(
        'lib/source_parser/download_engines/youtube_download_engine.dart#download: explode stream=${streamInfo.container.name} size=${streamInfo.size.totalBytes}',
      );

      final safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
      task.fileName = '$safeTitle.${streamInfo.container.name}';
      onProgressUpdated();

      final outFile = await _awaitUnlessCanceled(
        _uniqueFile(directory, task.fileName),
        isCancelRequested,
      );
      outputFile = outFile;
      task.totalBytes = streamInfo.size.totalBytes;
      task.filePath = outFile.path;
      task.receivedBytes = 0;
      task.progress = 0;
      task.statusDetail = 'YouTube：正在下载视频流…';
      onProgressUpdated();

      final mediaStream = yt.videos.streamsClient.get(streamInfo);
      final sink = outFile.openWrite();
      try {
        await for (final chunk in mediaStream) {
          if (isCancelRequested()) {
            throw const DownloadCanceledException();
          }

          task.receivedBytes += chunk.length;
          if (task.statusDetail != null) {
            task.statusDetail = null;
          }
          final totalBytes = task.totalBytes;
          if (totalBytes != null && totalBytes > 0) {
            task.progress = task.receivedBytes / totalBytes;
          }

          sink.add(chunk);
          onProgressUpdated();
        }
      } finally {
        await sink.close();
      }

      return outFile;
    } on DownloadCanceledException {
      await outputFile?.deleteIfExists();
      rethrow;
    } on Object catch (error) {
      await outputFile?.deleteIfExists();
      task.addLog(
        'lib/source_parser/download_engines/youtube_download_engine.dart#download: explode failed error=$error',
      );

      if (!settings.enableYtDlpFallback) {
        throw DownloadException(_friendlyYouTubeError(error));
      }

      try {
        task.addLog(
          'lib/source_parser/download_engines/youtube_download_engine.dart#download: fallback=yt-dlp start',
        );
        task.statusDetail = 'YouTube：改用 yt-dlp（首次可能较慢）…';
        onProgressUpdated();
        final fallbackFile = await _downloadViaYtDlp(
          task: task,
          directory: directory,
          settings: settings,
          processRunner: processRunner,
          processStarter: processStarter,
          isCancelRequested: isCancelRequested,
          onProgressUpdated: onProgressUpdated,
        );
        return fallbackFile;
      } on Object catch (ytDlpError) {
        task.addLog(
          'lib/source_parser/download_engines/youtube_download_engine.dart#download: fallback=yt-dlp failed error=$ytDlpError',
        );
        throw DownloadException(
          '${_friendlyYouTubeError(error)}；yt-dlp 兜底也失败: $ytDlpError',
        );
      }
    } finally {
      yt.close();
    }
  }

  Future<StreamManifest> _getManifestWithFallback(
    YoutubeExplode yt,
    String videoId,
  ) async {
    final clients = <List<YoutubeApiClient>>[
      [YoutubeApiClient.ios, YoutubeApiClient.safari],
      [YoutubeApiClient.android, YoutubeApiClient.ios],
      [YoutubeApiClient.mweb, YoutubeApiClient.ios],
      [YoutubeApiClient.tv, YoutubeApiClient.ios],
    ];

    Object? lastError;
    for (final clientPair in clients) {
      try {
        final manifest = await yt.videos.streamsClient.getManifest(
          videoId,
          ytClients: clientPair,
        );
        if (manifest.streams.isNotEmpty) {
          return manifest;
        }
      } on Object catch (error) {
        lastError = error;
      }
    }

    if (lastError != null) {
      throw lastError;
    }

    throw const DownloadException('未获取到可用的视频流');
  }

  static StreamInfo? _pickYoutubeStreamInfo(StreamManifest manifest) {
    if (manifest.muxed.isNotEmpty) {
      return manifest.muxed.withHighestBitrate();
    }

    final hlsMuxed = manifest.streams.whereType<HlsMuxedStreamInfo>().toList();
    if (hlsMuxed.isNotEmpty) {
      return hlsMuxed.withHighestBitrate();
    }

    if (manifest.videoOnly.isNotEmpty) {
      return manifest.videoOnly.withHighestBitrate();
    }

    if (manifest.audioOnly.isNotEmpty) {
      return manifest.audioOnly.withHighestBitrate();
    }

    return null;
  }

  Future<File> _downloadViaYtDlp({
    required DownloadTask task,
    required Directory directory,
    required DownloadSettings settings,
    required ProcessRunner processRunner,
    required ProcessStarter processStarter,
    required CancelCheck isCancelRequested,
    required void Function() onProgressUpdated,
  }) async {
    final beforePaths = await _listFilePaths(directory);
    final args = _buildYtDlpArgs(
      task: task,
      directory: directory,
      settings: settings,
    );

    Process process;
    try {
      process = await processStarter('yt-dlp', args);
    } on ProcessException catch (error) {
      final detail = error.message;
      if (detail.contains('Operation not permitted')) {
        throw const DownloadException(
          '系统禁止当前应用执行外部命令（可能是 macOS 沙箱限制），请关闭沙箱或改为非沙箱运行后重试',
        );
      }
      throw DownloadException('未检测到 yt-dlp，请先安装后重试（${error.message}）');
    }

    if (isCancelRequested()) {
      process.kill(ProcessSignal.sigterm);
      throw const DownloadCanceledException();
    }

    task.statusDetail = 'YouTube：yt-dlp 下载中…';
    onProgressUpdated();

    final stderrBuffer = StringBuffer();
    final stdoutBuffer = StringBuffer();
    final reportedPaths = <String>{};
    var canceled = false;

    void maybeCancel() {
      if (!canceled && isCancelRequested()) {
        canceled = true;
        process.kill(ProcessSignal.sigterm);
      }
    }

    void handleProgressLine(String line) {
      maybeCancel();
      final trimmed = line.trim();
      _collectReportedPath(trimmed, reportedPaths);
      final progressMatch = RegExp(
        r'\[download\]\s+(\d+(?:\.\d+)?)%',
      ).firstMatch(trimmed);
      if (progressMatch == null) {
        return;
      }

      final percent = double.tryParse(progressMatch.group(1) ?? '');
      if (percent == null) {
        return;
      }

      final clampedPercent = percent.clamp(0, 100);
      task.progress = clampedPercent / 100;
      task.statusDetail = null;

      final totalMatch = RegExp(
        r'of\s+([0-9.]+)([KMGTP]i?B)',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (totalMatch != null) {
        final totalBytes = _parseByteSize(
          totalMatch.group(1) ?? '',
          totalMatch.group(2) ?? '',
        );
        if (totalBytes != null && totalBytes > 0) {
          task.totalBytes = totalBytes;
          task.receivedBytes = (totalBytes * task.progress).round();
        }
      }
      onProgressUpdated();
    }

    Future<void> drainStream(
      Stream<List<int>> stream, {
      required bool isStderr,
    }) async {
      final lines = utf8.decoder
          .bind(stream)
          .transform(const LineSplitter())
          .handleError((_) {});
      await for (final line in lines) {
        maybeCancel();
        if (isStderr) {
          stderrBuffer.writeln(line);
        } else {
          stdoutBuffer.writeln(line);
        }
        handleProgressLine(line);
      }
    }

    int exitCode;
    try {
      await Future.wait([
        drainStream(process.stdout, isStderr: false),
        drainStream(process.stderr, isStderr: true),
      ]);
      maybeCancel();
      exitCode = await process.exitCode;
    } on Object catch (error) {
      task.addLog(
        'lib/source_parser/download_engines/youtube_download_engine.dart#_downloadViaYtDlp: stream mode failed, fallback to legacy mode error=$error',
      );
      process.kill(ProcessSignal.sigterm);
        return _downloadViaYtDlpLegacy(
          task: task,
          directory: directory,
          args: args,
          beforePaths: beforePaths,
          processRunner: processRunner,
          reportedPaths: reportedPaths,
          onProgressUpdated: onProgressUpdated,
          isCancelRequested: isCancelRequested,
        );
    }
    task.addLog(
      'lib/source_parser/download_engines/youtube_download_engine.dart#_downloadViaYtDlp: exit=$exitCode',
    );
    if (canceled) {
      throw const DownloadCanceledException();
    }
    if (exitCode != 0) {
      final err = stderrBuffer.toString().trim();
      final out = stdoutBuffer.toString().trim();
      final detail = err.isNotEmpty ? err : out;
      if (_isProxyConnectionFailure(detail)) {
        task.addLog(
          'lib/source_parser/download_engines/youtube_download_engine.dart#_downloadViaYtDlp: detected proxy failure, retry with --proxy ""',
        );
        final noProxyArgs = [...args, '--proxy', ''];
        return _downloadViaYtDlpLegacy(
          task: task,
          directory: directory,
          args: noProxyArgs,
          beforePaths: beforePaths,
          processRunner: processRunner,
          reportedPaths: reportedPaths,
          onProgressUpdated: onProgressUpdated,
          allowProxyRetry: false,
          isCancelRequested: isCancelRequested,
        );
      }
      throw DownloadException(_friendlyYtDlpError(detail, exitCode));
    }

    return _pickDownloadedFileAndUpdateTask(
      task: task,
      directory: directory,
      beforePaths: beforePaths,
      reportedPaths: reportedPaths,
      onProgressUpdated: onProgressUpdated,
    );
  }

  List<String> _buildYtDlpArgs({
    required DownloadTask task,
    required Directory directory,
    required DownloadSettings settings,
  }) {
    final outputTemplate = '${directory.path}/%(title)s.%(ext)s';
    final ffmpegLocation = _existingExecutablePath('ffmpeg');

    return <String>[
      '--no-playlist',
      '--newline',
      '--progress',
      '--color',
      'never',
      '--print',
      'after_move:%(filepath)s',
      if (ffmpegLocation != null) ...['--ffmpeg-location', ffmpegLocation],
      '-N',
      settings.ytDlpConcurrency.toString(),
      '--retries',
      settings.ytDlpRetries.toString(),
      '--fragment-retries',
      settings.ytDlpFragmentRetries.toString(),
      '-f',
      'bv*+ba/best',
      '--merge-output-format',
      'mp4',
      '-o',
      outputTemplate,
      task.resource.url,
    ];
  }

  static String _friendlyYouTubeError(Object error) {
    final raw = error.toString();
    if (raw.contains('VideoUnavailableException')) {
      return 'YouTube 返回视频不可用（可能私有、地区限制、年龄限制或需要登录）';
    }
    if (raw.contains('429') || raw.contains('RequestLimitExceeded')) {
      return 'YouTube 请求过于频繁，请稍后重试或更换代理节点';
    }
    if (raw.contains('403') || raw.contains('forbidden')) {
      return 'YouTube 拒绝访问该视频流，可能受地区或权限限制';
    }
    if (raw.contains('404')) {
      return 'YouTube 视频不可用或已被移除';
    }
    if (raw.contains('VideoUnplayableException') ||
        raw.contains('playability')) {
      return '该视频当前不可播放（可能年龄限制/地区限制/版权限制）';
    }

    return 'lib/source_parser/download_engines/youtube_download_engine.dart: $raw';
  }

  static String _friendlyYtDlpError(String raw, int exitCode) {
    if (raw.contains("Sign in to confirm you're not a bot")) {
      return 'yt-dlp 执行失败(exit=$exitCode): YouTube 触发机器人校验。请确认 Chrome 已登录 YouTube，并在 Chrome 中可直接访问该视频后重试。原始错误: $raw';
    }
    if (_isProxyConnectionFailure(raw)) {
      return 'yt-dlp 执行失败(exit=$exitCode): 代理连接失败。请检查代理设置，或关闭代理后重试。原始错误: $raw';
    }
    return 'yt-dlp 执行失败(exit=$exitCode): $raw';
  }

  static bool _isProxyConnectionFailure(String raw) {
    return raw.contains('Unable to connect to proxy') ||
        raw.contains('Tunnel connection failed');
  }

  static String? _existingExecutablePath(String executable) {
    for (final candidate in _executableCandidates(executable)) {
      if (candidate == executable) {
        continue;
      }
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  static List<String> _executableCandidates(String executable) {
    final home = Platform.environment['HOME'];
    final names = Platform.isWindows
        ? {executable, '$executable.exe'}
        : {executable};
    final directories = <String>[
      if (Platform.isMacOS) ...['/opt/homebrew/bin', '/usr/local/bin'],
      if (!Platform.isWindows) '/usr/bin',
      if (home != null && home.trim().isNotEmpty) '$home/.local/bin',
    ];

    return <String>[
      executable,
      for (final directory in directories)
        for (final name in names) '$directory/$name',
    ];
  }

  static Future<Set<String>> _listFilePaths(Directory directory) async {
    final files = await _listFiles(directory);
    return files.map((file) => file.path).toSet();
  }

  static Future<List<File>> _listFiles(Directory directory) async {
    final entities = await directory.list(recursive: false).toList();
    return entities.whereType<File>().toList();
  }

  static int? _parseByteSize(String numberText, String unitText) {
    final number = double.tryParse(numberText);
    if (number == null || number.isNaN || number.isInfinite) {
      return null;
    }

    final normalizedUnit = unitText.toUpperCase();
    final multiplier = switch (normalizedUnit) {
      'B' => 1,
      'KB' || 'KIB' => 1024,
      'MB' || 'MIB' => 1024 * 1024,
      'GB' || 'GIB' => 1024 * 1024 * 1024,
      'TB' || 'TIB' => 1024 * 1024 * 1024 * 1024,
      'PB' || 'PIB' => 1024 * 1024 * 1024 * 1024 * 1024,
      _ => 0,
    };
    if (multiplier == 0) {
      return null;
    }
    return (number * multiplier).round();
  }

  Future<File> _downloadViaYtDlpLegacy({
    required DownloadTask task,
    required Directory directory,
    required List<String> args,
    required Set<String> beforePaths,
    required ProcessRunner processRunner,
    required Set<String> reportedPaths,
    required void Function() onProgressUpdated,
    required CancelCheck isCancelRequested,
    bool allowProxyRetry = true,
  }) async {
    final result = await _awaitUnlessCanceled(
      processRunner('yt-dlp', args),
      isCancelRequested,
    );
    task.addLog(
      'lib/source_parser/download_engines/youtube_download_engine.dart#_downloadViaYtDlpLegacy: exit=${result.exitCode}',
    );
    if (result.exitCode != 0) {
      final err = (result.stderr ?? '').toString().trim();
      final out = (result.stdout ?? '').toString().trim();
      final detail = err.isNotEmpty ? err : out;
      if (allowProxyRetry && _isProxyConnectionFailure(detail)) {
        task.addLog(
          'lib/source_parser/download_engines/youtube_download_engine.dart#_downloadViaYtDlpLegacy: detected proxy failure, retry with --proxy ""',
        );
        final noProxyArgs = [...args, '--proxy', ''];
        return _downloadViaYtDlpLegacy(
          task: task,
          directory: directory,
          args: noProxyArgs,
          beforePaths: beforePaths,
          processRunner: processRunner,
          reportedPaths: reportedPaths,
          onProgressUpdated: onProgressUpdated,
          allowProxyRetry: false,
          isCancelRequested: isCancelRequested,
        );
      }
      throw DownloadException(_friendlyYtDlpError(detail, result.exitCode));
    }
    _collectReportedPath((result.stdout ?? '').toString(), reportedPaths);
    _collectReportedPath((result.stderr ?? '').toString(), reportedPaths);
    return _pickDownloadedFileAndUpdateTask(
      task: task,
      directory: directory,
      beforePaths: beforePaths,
      reportedPaths: reportedPaths,
      onProgressUpdated: onProgressUpdated,
    );
  }

  Future<File> _pickDownloadedFileAndUpdateTask({
    required DownloadTask task,
    required Directory directory,
    required Set<String> beforePaths,
    required Set<String> reportedPaths,
    required void Function() onProgressUpdated,
  }) async {
    final afterFiles = await _listFiles(directory);
    final createdFiles = afterFiles
        .where((file) => !beforePaths.contains(file.path))
        .toList();
    File? file;
    if (createdFiles.isNotEmpty) {
      createdFiles.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );
      file = createdFiles.first;
    } else {
      for (final path in reportedPaths.toList().reversed) {
        final candidate = File(path);
        if (await candidate.exists()) {
          file = candidate;
          break;
        }
      }
    }
    if (file == null) {
      throw const DownloadException('yt-dlp 已执行成功，但未定位到输出文件');
    }
    task.fileName = file.uri.pathSegments.last;
    task.filePath = file.path;
    task.progress = 1;
    task.totalBytes = await file.length();
    task.receivedBytes = task.totalBytes ?? 0;
    onProgressUpdated();
    return file;
  }

  static void _collectReportedPath(String raw, Set<String> collector) {
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (trimmed.startsWith('after_move:')) {
        final path = trimmed.substring('after_move:'.length).trim();
        if (path.isNotEmpty) {
          collector.add(path);
        }
      }
      if (trimmed.startsWith('[download] Destination:')) {
        final path = trimmed
            .substring('[download] Destination:'.length)
            .trim()
            .replaceAll('"', '');
        if (path.isNotEmpty) {
          collector.add(path);
        }
      }
      if (trimmed.startsWith('[Merger] Merging formats into')) {
        final path = trimmed
            .replaceFirst('[Merger] Merging formats into', '')
            .trim()
            .replaceAll('"', '');
        if (path.isNotEmpty) {
          collector.add(path);
        }
      }
    }
  }

  static Future<File> _uniqueFile(Directory directory, String fileName) async {
    final dotIndex = fileName.lastIndexOf('.');
    final name = dotIndex <= 0 ? fileName : fileName.substring(0, dotIndex);
    final ext = dotIndex <= 0 ? '' : fileName.substring(dotIndex);

    var index = 1;
    var file = File('${directory.path}/$fileName');
    while (await file.exists()) {
      index += 1;
      file = File('${directory.path}/$name-$index$ext');
    }
    return file;
  }
}

extension on File {
  Future<void> deleteIfExists() async {
    if (await exists()) {
      await delete();
    }
  }
}

class _NonClosingHttpClient extends http.BaseClient {
  _NonClosingHttpClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request);
  }

  @override
  void close() {
    // Keep shared client lifecycle controlled by DownloadQueueController.
  }
}
