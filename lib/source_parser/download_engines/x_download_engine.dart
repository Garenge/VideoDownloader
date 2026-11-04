import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../download_queue_controller.dart'
    show DownloadCanceledException, DownloadException, DownloadTask;
import '../download_settings.dart';
import '../x_login_bridge.dart';
import 'download_engine.dart';

class XDownloadEngine extends DownloadEngine {
  const XDownloadEngine();

  static const List<String> _preferredCookieBrowsers = <String>[
    'chrome',
    'edge',
    'chromium',
    'brave',
  ];

  static const List<String> _preferredTwitterApis = <String>[
    'graphql',
    'syndication',
  ];

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
    if (Platform.isMacOS) {
      try {
        final result = await XLoginBridge.withCookieFile(
          (cookieFilePath) => _downloadWithCookieFile(
            task: task,
            directory: directory,
            settings: settings,
            processRunner: processRunner,
            processStarter: processStarter,
            isCancelRequested: isCancelRequested,
            onProgressUpdated: onProgressUpdated,
            appCookieFilePath: cookieFilePath,
          ),
        );
        if (result != null) {
          return result;
        }
      } on PlatformException catch (error) {
        task.addLog(
          'lib/source_parser/download_engines/x_download_engine.dart#download: '
          'app login session unavailable error=${error.code}',
        );
      } on MissingPluginException {
        // Unit tests and non-macOS hosts do not register the native login bridge.
      }
    }
    return _downloadWithCookieFile(
      task: task,
      directory: directory,
      settings: settings,
      processRunner: processRunner,
      processStarter: processStarter,
      isCancelRequested: isCancelRequested,
      onProgressUpdated: onProgressUpdated,
    );
  }

  Future<File> _downloadWithCookieFile({
    required DownloadTask task,
    required Directory directory,
    required DownloadSettings settings,
    required ProcessRunner processRunner,
    required ProcessStarter processStarter,
    required CancelCheck isCancelRequested,
    required void Function() onProgressUpdated,
    String? appCookieFilePath,
  }) async {
    final plan = await _preparePlan(task, directory);

    try {
      final attempts = _buildAttemptPlans(
        task: task,
        outputTemplate: plan.outputTemplate,
        settings: settings,
        appCookieFilePath: appCookieFilePath,
      );
      Object? lastError;
      for (final attempt in attempts) {
        try {
          task.addLog(
            'lib/source_parser/download_engines/x_download_engine.dart#download: '
            'attempt label=${attempt.label} args=${attempt.args.join(" ")}',
          );
          return await _runYtDlpAttempt(
            task: task,
            directory: directory,
            plan: plan,
            attempt: attempt,
            processRunner: processRunner,
            processStarter: processStarter,
            isCancelRequested: isCancelRequested,
            onProgressUpdated: onProgressUpdated,
          );
        } on DownloadCanceledException {
          rethrow;
        } on DownloadException catch (error) {
          lastError = error;
          task.addLog(
            'lib/source_parser/download_engines/x_download_engine.dart#download: '
            'attempt failed label=${attempt.label} error=$error',
          );
          if (!_shouldRetryNextAttempt(error.message)) {
            rethrow;
          }
        }
      }

      if (lastError is DownloadException) {
        throw lastError;
      }
      throw const DownloadException('X 下载失败：所有 yt-dlp 尝试均未成功');
    } on DownloadCanceledException {
      await _deleteDirectoryIfExists(plan.workspaceDirectory);
      rethrow;
    } on Object {
      await _deleteDirectoryIfExists(plan.workspaceDirectory);
      rethrow;
    }
  }

  List<String> _buildArgs({
    required DownloadTask task,
    required String outputTemplate,
    required DownloadSettings settings,
    String? cookiesFromBrowser,
    String? cookiesFile,
    String? twitterApi,
  }) {
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
      if (cookiesFile != null) ...[
        '--cookies',
        cookiesFile,
      ] else if (cookiesFromBrowser != null) ...[
        '--cookies-from-browser',
        cookiesFromBrowser,
      ],
      if (twitterApi != null) ...[
        '--extractor-args',
        'twitter:api=$twitterApi',
      ],
      '-o',
      outputTemplate,
      task.resource.url,
    ];
  }

  List<_XAttemptPlan> _buildAttemptPlans({
    required DownloadTask task,
    required String outputTemplate,
    required DownloadSettings settings,
    String? appCookieFilePath,
  }) {
    final attempts = <_XAttemptPlan>[];
    if (appCookieFilePath != null) {
      for (final api in _preferredTwitterApis) {
        attempts.add(
          _XAttemptPlan(
            label: 'app-login api:$api',
            args: _buildArgs(
              task: task,
              outputTemplate: outputTemplate,
              settings: settings,
              cookiesFile: appCookieFilePath,
              twitterApi: api,
            ),
          ),
        );
      }
    }
    for (final browser in _preferredCookieBrowsers) {
      for (final api in _preferredTwitterApis) {
        attempts.add(
          _XAttemptPlan(
            label: 'cookies:$browser api:$api',
            args: _buildArgs(
              task: task,
              outputTemplate: outputTemplate,
              settings: settings,
              cookiesFromBrowser: browser,
              twitterApi: api,
            ),
          ),
        );
      }
    }

    for (final api in _preferredTwitterApis) {
      attempts.add(
        _XAttemptPlan(
          label: 'anonymous api:$api',
          args: _buildArgs(
            task: task,
            outputTemplate: outputTemplate,
            settings: settings,
            twitterApi: api,
          ),
        ),
      );
    }
    return attempts;
  }

  Future<File> _runYtDlpAttempt({
    required DownloadTask task,
    required Directory directory,
    required _XYtDlpPlan plan,
    required _XAttemptPlan attempt,
    required ProcessRunner processRunner,
    required ProcessStarter processStarter,
    required CancelCheck isCancelRequested,
    required void Function() onProgressUpdated,
  }) async {
    final args = attempt.args;
    Process process;
    try {
      process = await processStarter('yt-dlp', args);
    } on ProcessException catch (error) {
      final detail = error.message;
      if (detail.contains('Operation not permitted')) {
        throw const DownloadException(
          '系统禁止当前应用执行外部命令（可能是 macOS 沙箱限制），X 下载不可用，请关闭沙箱或改为非沙箱运行后重试',
        );
      }
      if (_looksLikeMissingBrowserCookies(detail)) {
        throw DownloadException('浏览器 cookies 不可用：$detail');
      }
      throw DownloadException('未检测到 yt-dlp，X 下载不可用（${error.message}）');
    }

    if (isCancelRequested()) {
      process.kill(ProcessSignal.sigterm);
      throw const DownloadCanceledException();
    }

    task.statusDetail = 'X：yt-dlp 下载中…';
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
        'lib/source_parser/download_engines/x_download_engine.dart#_runYtDlpAttempt: '
        'stream mode failed, fallback to legacy mode label=${attempt.label} error=$error',
      );
      process.kill(ProcessSignal.sigterm);
      return _downloadLegacy(
        task: task,
        plan: plan,
        args: args,
        processRunner: processRunner,
        reportedPaths: reportedPaths,
        onProgressUpdated: onProgressUpdated,
        isCancelRequested: isCancelRequested,
      );
    }

    task.addLog(
      'lib/source_parser/download_engines/x_download_engine.dart#_runYtDlpAttempt: '
      'label=${attempt.label} exit=$exitCode',
    );
    if (canceled) {
      throw const DownloadCanceledException();
    }
    if (exitCode != 0) {
      final err = stderrBuffer.toString().trim();
      final out = stdoutBuffer.toString().trim();
      final detail = err.isNotEmpty ? err : out;
      throw DownloadException(_friendlyXError(detail, exitCode));
    }

    return _finalizeDownload(
      task: task,
      directory: directory,
      plan: plan,
      reportedPaths: reportedPaths,
      onProgressUpdated: onProgressUpdated,
    );
  }

  Future<_XYtDlpPlan> _preparePlan(
    DownloadTask task,
    Directory directory,
  ) async {
    final workspaceDirectory = Directory(
      '${directory.path}/.videodownloader_x/${task.id}',
    );
    await _deleteDirectoryIfExists(workspaceDirectory);
    await workspaceDirectory.create(recursive: true);
    final suggestedBaseName = _suggestBaseName(task);
    task.fileName = '$suggestedBaseName.mp4';
    task.filePath = null;
    task.progress = 0;
    task.receivedBytes = 0;
    task.totalBytes = null;
    task.addLog(
      'lib/source_parser/download_engines/x_download_engine.dart#_preparePlan: '
      'workspace=${workspaceDirectory.path} target=${task.fileName}',
    );
    return _XYtDlpPlan(
      targetDirectory: directory,
      workspaceDirectory: workspaceDirectory,
      outputTemplate: '${workspaceDirectory.path}/download.%(ext)s',
      suggestedBaseName: suggestedBaseName,
    );
  }

  Future<File> _finalizeDownload({
    required DownloadTask task,
    required Directory directory,
    required _XYtDlpPlan plan,
    required Set<String> reportedPaths,
    required void Function() onProgressUpdated,
  }) async {
    try {
      final stagedFile = await _pickStagedDownloadedFile(
        task: task,
        workspaceDirectory: plan.workspaceDirectory,
        reportedPaths: reportedPaths,
      );
      final ext = _resolvedExtension(stagedFile.path);
      final targetFile = await _uniqueFile(
        directory,
        '${plan.suggestedBaseName}.$ext',
      );
      final movedFile = await _moveFile(stagedFile, targetFile);
      task.fileName = movedFile.uri.pathSegments.last;
      task.filePath = movedFile.path;
      task.progress = 1;
      task.totalBytes = await movedFile.length();
      task.receivedBytes = task.totalBytes ?? 0;
      onProgressUpdated();
      return movedFile;
    } finally {
      await _deleteDirectoryIfExists(plan.workspaceDirectory);
    }
  }

  Future<File> _downloadLegacy({
    required DownloadTask task,
    required _XYtDlpPlan plan,
    required List<String> args,
    required ProcessRunner processRunner,
    required Set<String> reportedPaths,
    required void Function() onProgressUpdated,
    required CancelCheck isCancelRequested,
  }) async {
    final result = await _awaitUnlessCanceled(
      processRunner('yt-dlp', args),
      isCancelRequested,
    );
    task.addLog(
      'lib/source_parser/download_engines/x_download_engine.dart#_downloadLegacy: exit=${result.exitCode}',
    );
    if (result.exitCode != 0) {
      final err = (result.stderr ?? '').toString().trim();
      final out = (result.stdout ?? '').toString().trim();
      final detail = err.isNotEmpty ? err : out;
      throw DownloadException(_friendlyXError(detail, result.exitCode));
    }
    _collectReportedPath((result.stdout ?? '').toString(), reportedPaths);
    _collectReportedPath((result.stderr ?? '').toString(), reportedPaths);
    return _finalizeDownload(
      task: task,
      directory: plan.targetDirectory,
      plan: plan,
      reportedPaths: reportedPaths,
      onProgressUpdated: onProgressUpdated,
    );
  }

  Future<File> _pickStagedDownloadedFile({
    required DownloadTask task,
    required Directory workspaceDirectory,
    required Set<String> reportedPaths,
  }) async {
    for (final path in reportedPaths.toList().reversed) {
      final candidate = File(path);
      if (await candidate.exists()) {
        return candidate;
      }
    }

    final workspaceFiles = await _listFiles(
      workspaceDirectory,
      recursive: false,
    );
    final mediaFiles = workspaceFiles
        .where((file) => !_isTemporaryArtifact(file.path))
        .where((file) => !_isAuxiliaryFile(file.path))
        .toList();
    if (mediaFiles.isEmpty) {
      task.addLog(
        'lib/source_parser/download_engines/x_download_engine.dart#_pickStagedDownloadedFile: '
        'empty_workspace workspace=${workspaceDirectory.path} files=${workspaceFiles.map((file) => file.path).join(" | ")}',
      );
      throw const DownloadException('yt-dlp 已执行成功，但当前 X 任务工作区没有找到下载结果');
    }

    mediaFiles.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    if (mediaFiles.length > 1) {
      task.addLog(
        'lib/source_parser/download_engines/x_download_engine.dart#_pickStagedDownloadedFile: '
        'multiple_outputs files=${mediaFiles.map((file) => file.path).join(" | ")}',
      );
    }
    return mediaFiles.first;
  }

  String _suggestBaseName(DownloadTask task) {
    final rawTitle = task.resource.title.trim();
    final strippedTitle = rawTitle
        .replaceFirst(RegExp(r'^X\s*视频\s*[：:]\s*'), '')
        .trim();
    final preferredTitle = strippedTitle.isEmpty || strippedTitle == 'X 视频'
        ? 'x_video'
        : strippedTitle;
    final sanitized = preferredTitle
        .replaceAll('@', '')
        .replaceAll('/', '_')
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return sanitized.isEmpty ? 'x_video' : sanitized;
  }

  static String _friendlyXError(String raw, int exitCode) {
    if (raw.contains('No video could be found in this tweet')) {
      return 'yt-dlp 执行失败(exit=$exitCode): 这条推文里没有检测到可下载的视频媒体，可能是图片推文、纯文本推文，或当前公开页面未暴露视频资源。原始错误: $raw';
    }
    if (raw.contains('Login required') ||
        raw.contains('Sign in to confirm') ||
        raw.contains('requested tweet may only be available')) {
      return 'yt-dlp 执行失败(exit=$exitCode): 该 X 内容可能需要登录、受可见性限制，或当前环境无法访问。请确认浏览器中可正常打开该推文后重试。原始错误: $raw';
    }
    if (raw.contains('Private') || raw.contains('private')) {
      return 'yt-dlp 执行失败(exit=$exitCode): 该推文可能是私密内容，当前无法直接下载。原始错误: $raw';
    }
    if (raw.contains('429') || raw.contains('rate limit')) {
      return 'yt-dlp 执行失败(exit=$exitCode): X 请求过于频繁，请稍后重试。原始错误: $raw';
    }
    if (raw.contains('403') || raw.contains('Unauthorized')) {
      return 'yt-dlp 执行失败(exit=$exitCode): X 拒绝访问该内容，可能需要登录或受地区/权限限制。原始错误: $raw';
    }
    if (raw.contains('404') || raw.contains('not found')) {
      return 'yt-dlp 执行失败(exit=$exitCode): 推文不存在、已删除，或当前不可见。原始错误: $raw';
    }
    return 'yt-dlp 执行失败(exit=$exitCode): $raw';
  }

  static bool _shouldRetryNextAttempt(String message) {
    return message.contains('No video could be found in this tweet') ||
        message.contains('cookies 不可用') ||
        message.contains('Read timed out') ||
        message.contains('Unable to download JSON metadata') ||
        message.contains('HTTP Error 404');
  }

  static bool _looksLikeMissingBrowserCookies(String raw) {
    return raw.contains('could not find chrome cookies database') ||
        raw.contains('Could not copy Chrome cookie database') ||
        raw.contains('browser is not supported') ||
        raw.contains('could not find edge cookies database') ||
        raw.contains('Failed to decrypt with DPAPI') ||
        raw.contains('Failed to decrypt');
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

  static Future<List<File>> _listFiles(
    Directory directory, {
    bool recursive = false,
  }) async {
    final entities = await directory.list(recursive: recursive).toList();
    return entities.whereType<File>().toList();
  }

  static bool _isTemporaryArtifact(String path) {
    final lowered = path.toLowerCase();
    return lowered.endsWith('.part') ||
        lowered.endsWith('.ytdl') ||
        lowered.endsWith('.temp');
  }

  static bool _isAuxiliaryFile(String path) {
    final lowered = path.toLowerCase();
    return lowered.endsWith('.json') ||
        lowered.endsWith('.description') ||
        lowered.endsWith('.srt') ||
        lowered.endsWith('.vtt');
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

  static String _resolvedExtension(String path) {
    final name = path.split('/').last;
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == name.length - 1) {
      return 'mp4';
    }
    final ext = name.substring(dotIndex + 1).trim().toLowerCase();
    if (ext.isEmpty || ext.length > 8) {
      return 'mp4';
    }
    return ext;
  }

  Future<File> _moveFile(File source, File target) async {
    try {
      return await source.rename(target.path);
    } on FileSystemException {
      final copied = await source.copy(target.path);
      await source.deleteIfExists();
      return copied;
    }
  }

  Future<void> _deleteDirectoryIfExists(Directory directory) async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
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
}

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

extension on File {
  Future<void> deleteIfExists() async {
    if (await exists()) {
      await delete();
    }
  }
}

final class _XYtDlpPlan {
  const _XYtDlpPlan({
    required this.targetDirectory,
    required this.workspaceDirectory,
    required this.outputTemplate,
    required this.suggestedBaseName,
  });

  final Directory targetDirectory;
  final Directory workspaceDirectory;
  final String outputTemplate;
  final String suggestedBaseName;
}

final class _XAttemptPlan {
  const _XAttemptPlan({required this.label, required this.args});

  final String label;
  final List<String> args;
}
