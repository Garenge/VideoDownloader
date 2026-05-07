import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'download_history_store.dart';
import 'download_queue_controller.dart' show ProcessStarter, DownloadException;

typedef ConversionHistoryRecorder =
    Future<void> Function(DownloadHistoryRecord record);

enum MediaConversionStatus {
  pending('等待中'),
  converting('转换中'),
  completed('已完成'),
  failed('失败'),
  canceled('已取消');

  const MediaConversionStatus(this.displayName);

  final String displayName;
}

class MediaConversionTask {
  MediaConversionTask({
    required this.id,
    required this.inputRecord,
    required this.outputFileName,
  });

  final String id;
  final DownloadHistoryRecord inputRecord;
  String outputFileName;

  MediaConversionStatus status = MediaConversionStatus.pending;
  double progress = 0;
  String? outputFilePath;
  String? errorMessage;
  String? failureSummary;
  String? statusDetail;
  DateTime? activeStartedAt;
  final List<String> _logs = [];

  List<String> get logs => List.unmodifiable(_logs);
  String get logText => _logs.join('\n');

  void clearLogs() {
    _logs.clear();
  }

  void addLog(String message) {
    final timestamp = DateTime.now().toIso8601String();
    _logs.add('[$timestamp] $message');
  }

  String get progressLabel {
    if (status == MediaConversionStatus.completed) {
      return '100%';
    }
    if (status == MediaConversionStatus.pending) {
      return '排队等待中…';
    }
    if (status == MediaConversionStatus.converting) {
      final percent = (progress * 100).clamp(0, 100).toStringAsFixed(0);
      return progress > 0 ? '$percent%' : '正在分析媒体信息…';
    }
    return progress > 0
        ? '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%'
        : '未完成';
  }
}

class MediaConversionController extends ChangeNotifier {
  MediaConversionController({
    required ConversionHistoryRecorder historyRecorder,
    ProcessStarter? processStarter,
  }) : _historyRecorder = historyRecorder,
       _processStarter = processStarter ?? _defaultProcessStarter;

  final ConversionHistoryRecorder _historyRecorder;
  final ProcessStarter _processStarter;
  final List<MediaConversionTask> _tasks = [];
  final Set<String> _cancelRequestedTaskIds = {};

  Process? _activeProcess;
  bool _isRunning = false;
  Timer? _conversionElapsedTicker;

  List<MediaConversionTask> get tasks => List.unmodifiable(_tasks);

  MediaConversionTask enqueueM3u8ToMp4(DownloadHistoryRecord record) {
    final task = MediaConversionTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      inputRecord: record,
      outputFileName: _outputFileNameFor(record.fileName),
    );
    _tasks.insert(0, task);
    notifyListeners();
    unawaited(_runNext());
    return task;
  }

  void cancel(MediaConversionTask task) {
    if (task.status == MediaConversionStatus.pending) {
      task.status = MediaConversionStatus.canceled;
      notifyListeners();
      return;
    }

    if (task.status == MediaConversionStatus.converting) {
      _cancelRequestedTaskIds.add(task.id);
      _activeProcess?.kill(ProcessSignal.sigterm);
      notifyListeners();
    }
  }

  void retry(MediaConversionTask task) {
    if (task.status != MediaConversionStatus.failed) {
      return;
    }

    task.status = MediaConversionStatus.pending;
    task.progress = 0;
    task.outputFilePath = null;
    task.errorMessage = null;
    task.failureSummary = null;
    task.statusDetail = null;
    task.activeStartedAt = null;
    task.outputFileName = _outputFileNameFor(task.inputRecord.fileName);
    task.clearLogs();
    task.addLog(
      'lib/source_parser/media_conversion_controller.dart#retry: 用户触发重试',
    );
    _cancelRequestedTaskIds.remove(task.id);
    notifyListeners();
    unawaited(_runNext());
  }

  @override
  void dispose() {
    _stopConversionElapsedTicker();
    _activeProcess?.kill(ProcessSignal.sigterm);
    _activeProcess = null;
    super.dispose();
  }

  Future<void> _runNext() async {
    if (_isRunning) {
      return;
    }

    final task = _tasks.reversed
        .where((item) => item.status == MediaConversionStatus.pending)
        .firstOrNull;
    if (task == null) {
      return;
    }

    _isRunning = true;
    await _convert(task);
    _isRunning = false;
    unawaited(_runNext());
  }

  Future<void> _convert(MediaConversionTask task) async {
    File? outputFile;
    try {
      task.clearLogs();
      task.addLog(
        'lib/source_parser/media_conversion_controller.dart#_convert: start input=${task.inputRecord.filePath}',
      );
      task.status = MediaConversionStatus.converting;
      task.errorMessage = null;
      task.failureSummary = null;
      task.statusDetail = '准备启动 ffmpeg…';
      task.activeStartedAt = DateTime.now();
      _startConversionElapsedTicker();
      notifyListeners();

      final inputFile = File(task.inputRecord.filePath);
      if (!await inputFile.exists()) {
        throw DownloadException('待转换文件不存在：${task.inputRecord.filePath}');
      }
      if (!task.inputRecord.isM3u8) {
        throw const DownloadException('当前仅支持 m3u8 转 MP4');
      }

      final outputDirectory = inputFile.parent;
      outputFile = await _uniqueFile(outputDirectory, task.outputFileName);
      task.outputFilePath = outputFile.path;
      task.addLog(
        'lib/source_parser/media_conversion_controller.dart#_convert: output=${outputFile.path}',
      );

      final process = await _startFfmpegProcess(inputFile.path, outputFile.path);
      _activeProcess = process;
      if (_cancelRequestedTaskIds.contains(task.id)) {
        process.kill(ProcessSignal.sigterm);
        throw const _MediaConversionCanceledException();
      }

      await _trackFfmpegProgress(task, process);

      final exitCode = await process.exitCode;
      task.addLog(
        'lib/source_parser/media_conversion_controller.dart#_convert: ffmpeg exit=$exitCode',
      );
      if (_cancelRequestedTaskIds.contains(task.id)) {
        throw const _MediaConversionCanceledException();
      }
      if (exitCode != 0) {
        throw DownloadException(
          _buildReadableFfmpegFailureFromTask(task) ??
              'ffmpeg 执行失败(exit=$exitCode)，请查看转换日志定位原因',
        );
      }
      if (!await outputFile.exists()) {
        throw const DownloadException('ffmpeg 已结束，但未找到输出文件');
      }

      task.progress = 1;
      task.status = MediaConversionStatus.completed;
      task.statusDetail = null;
      task.activeStartedAt = null;
      await _historyRecorder(
        DownloadHistoryRecord(
          fileName: outputFile.uri.pathSegments.last,
          filePath: outputFile.path,
          sourceUrl: task.inputRecord.sourceUrl,
          completedAt: DateTime.now(),
        ),
      );
      notifyListeners();
    } on _MediaConversionCanceledException {
      _cancelRequestedTaskIds.remove(task.id);
      task.status = MediaConversionStatus.canceled;
      task.errorMessage = null;
      task.failureSummary = null;
      task.statusDetail = null;
      task.activeStartedAt = null;
      task.addLog(
        'lib/source_parser/media_conversion_controller.dart#_convert: canceled by user',
      );
      await outputFile?.deleteIfExists();
      notifyListeners();
    } on Object catch (error) {
      task.status = MediaConversionStatus.failed;
      task.errorMessage = _friendlyConversionError(error);
      task.statusDetail = null;
      task.activeStartedAt = null;
      task.addLog(
        'lib/source_parser/media_conversion_controller.dart#_convert: failed error=$error',
      );
      await outputFile?.deleteIfExists();
      notifyListeners();
    } finally {
      _activeProcess = null;
      _stopConversionElapsedTicker();
    }
  }

  Future<Process> _startFfmpegProcess(
    String inputFilePath,
    String outputFilePath,
  ) async {
    try {
      return await _processStarter('ffmpeg', [
        '-y',
        '-allowed_extensions',
        'ALL',
        '-protocol_whitelist',
        'file,http,https,tcp,tls,crypto',
        '-i',
        inputFilePath,
        '-c',
        'copy',
        '-bsf:a',
        'aac_adtstoasc',
        '-movflags',
        '+faststart',
        '-progress',
        'pipe:1',
        '-nostats',
        outputFilePath,
      ]);
    } on ProcessException catch (error) {
      final detail = error.message;
      if (detail.contains('Operation not permitted')) {
        throw const DownloadException(
          '系统禁止当前应用执行外部命令（可能是 macOS 沙箱限制），无法执行 ffmpeg',
        );
      }
      throw DownloadException('未检测到 ffmpeg，请先安装后重试（${error.message}）');
    }
  }

  Future<void> _trackFfmpegProgress(
    MediaConversionTask task,
    Process process,
  ) async {
    int? totalDurationUs;
    final stderrLines = <String>[];

    Future<void> drainStdout() async {
      final lines = utf8.decoder
          .bind(process.stdout)
          .transform(const LineSplitter())
          .handleError((_) {});
      await for (final line in lines) {
        if (_cancelRequestedTaskIds.contains(task.id)) {
          process.kill(ProcessSignal.sigterm);
          throw const _MediaConversionCanceledException();
        }

        final splitIndex = line.indexOf('=');
        if (splitIndex <= 0) {
          continue;
        }

        final key = line.substring(0, splitIndex).trim();
        final value = line.substring(splitIndex + 1).trim();
        if (key == 'progress') {
          task.addLog(
            'lib/source_parser/media_conversion_controller.dart#_trackFfmpegProgress: progress=$value',
          );
        }
        if (key == 'out_time_us') {
          final currentUs = int.tryParse(value);
          if (currentUs != null && currentUs > 0) {
            if (totalDurationUs != null && totalDurationUs! > 0) {
              task.progress = (currentUs / totalDurationUs!).clamp(0.0, 1.0);
              task.statusDetail =
                  '已处理 ${_formatDurationUs(currentUs)} / ${_formatDurationUs(totalDurationUs!)}';
            } else {
              task.statusDetail = '已处理 ${_formatDurationUs(currentUs)}';
            }
            notifyListeners();
          }
        } else if (key == 'progress' && value == 'end') {
          task.progress = 1;
          notifyListeners();
        }
      }
    }

    Future<void> drainStderr() async {
      final lines = utf8.decoder
          .bind(process.stderr)
          .transform(const LineSplitter())
          .handleError((_) {});
      await for (final line in lines) {
        if (_cancelRequestedTaskIds.contains(task.id)) {
          process.kill(ProcessSignal.sigterm);
          throw const _MediaConversionCanceledException();
        }

        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          stderrLines.add(trimmed);
          if (stderrLines.length > 60) {
            stderrLines.removeAt(0);
          }
          task.addLog(
            'lib/source_parser/media_conversion_controller.dart#_trackFfmpegProgress: ffmpeg: $trimmed',
          );
        }

        final durationMatch = RegExp(
          r'Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)',
        ).firstMatch(line);
        if (durationMatch != null) {
          totalDurationUs = _durationMatchToMicroseconds(durationMatch);
          if (totalDurationUs != null) {
            task.statusDetail =
                '已识别时长 ${_formatDurationUs(totalDurationUs!)}，开始转封装…';
            notifyListeners();
          }
        }

        final lowered = line.toLowerCase();
        if (lowered.contains('error') || lowered.contains('failed')) {
          task.failureSummary = trimmed;
          task.errorMessage = _buildReadableFfmpegFailure(stderrLines);
        }
      }
    }

    await Future.wait([drainStdout(), drainStderr()]);
    if (task.failureSummary == null && stderrLines.isNotEmpty) {
      task.failureSummary = _pickLastMeaningfulStderrLine(stderrLines);
    }
  }

  void _startConversionElapsedTicker() {
    if (_conversionElapsedTicker != null) {
      return;
    }
    _conversionElapsedTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_tasks.any((t) => t.status == MediaConversionStatus.converting)) {
        _stopConversionElapsedTicker();
        return;
      }
      notifyListeners();
    });
  }

  void _stopConversionElapsedTicker() {
    _conversionElapsedTicker?.cancel();
    _conversionElapsedTicker = null;
  }

  static String _friendlyConversionError(Object error) {
    if (error is DownloadException) {
      return error.message;
    }
    return 'lib/source_parser/media_conversion_controller.dart#_convert: $error';
  }

  static String? _buildReadableFfmpegFailureFromTask(MediaConversionTask task) {
    final summary = task.failureSummary?.trim();
    if (summary == null || summary.isEmpty) {
      return task.errorMessage;
    }
    return 'ffmpeg 转换失败：$summary';
  }

  static String _buildReadableFfmpegFailure(List<String> stderrLines) {
    final summary = _pickLastMeaningfulStderrLine(stderrLines);
    if (summary == null || summary.isEmpty) {
      return 'ffmpeg 转换失败，请复制转换日志查看详细原因';
    }
    return 'ffmpeg 转换失败：$summary';
  }

  static String? _pickLastMeaningfulStderrLine(List<String> lines) {
    for (final line in lines.reversed) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final lowered = trimmed.toLowerCase();
      final isBoilerplate =
          lowered.startsWith('ffmpeg version') ||
          lowered.startsWith('configuration:') ||
          lowered.startsWith('libav') ||
          lowered.startsWith('built with') ||
          lowered.startsWith('duration:') ||
          lowered.startsWith('stream #') ||
          lowered.startsWith('input #') ||
          lowered.startsWith('output #') ||
          lowered.startsWith('metadata:') ||
          lowered.startsWith('encoder ') ||
          lowered.startsWith('press [q]');
      if (!isBoilerplate) {
        return trimmed;
      }
    }
    return null;
  }

  static String _outputFileNameFor(String inputFileName) {
    final dotIndex = inputFileName.lastIndexOf('.');
    final baseName = dotIndex <= 0
        ? inputFileName
        : inputFileName.substring(0, dotIndex);
    return '$baseName.mp4';
  }

  static Future<File> _uniqueFile(Directory directory, String fileName) async {
    final dotIndex = fileName.lastIndexOf('.');
    final baseName = dotIndex <= 0 ? fileName : fileName.substring(0, dotIndex);
    final extension = dotIndex <= 0 ? '' : fileName.substring(dotIndex);

    var index = 1;
    var file = File('${directory.path}/$fileName');
    while (await file.exists()) {
      index += 1;
      file = File('${directory.path}/$baseName-$index$extension');
    }
    return file;
  }

  static int? _durationMatchToMicroseconds(RegExpMatch match) {
    final hours = int.tryParse(match.group(1) ?? '');
    final minutes = int.tryParse(match.group(2) ?? '');
    final seconds = double.tryParse(match.group(3) ?? '');
    if (hours == null || minutes == null || seconds == null) {
      return null;
    }
    return (((hours * 3600) + (minutes * 60)) * 1000000) +
        (seconds * 1000000).round();
  }

  static String _formatDurationUs(int microseconds) {
    final totalSeconds = microseconds ~/ 1000000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  static Future<Process> _defaultProcessStarter(
    String executable,
    List<String> arguments,
  ) async {
    ProcessException? lastNotFoundError;
    for (final candidate in _processExecutableCandidates(executable)) {
      try {
        return await Process.start(candidate, arguments);
      } on ProcessException catch (error) {
        if (!_isExecutableNotFound(error)) {
          rethrow;
        }
        lastNotFoundError = error;
      }
    }

    throw lastNotFoundError ??
        ProcessException(executable, arguments, 'No such file or directory');
  }

  static List<String> _processExecutableCandidates(String executable) {
    if (executable.contains('/') || executable.contains(r'\')) {
      return [executable];
    }

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

  static bool _isExecutableNotFound(ProcessException error) {
    final message = error.message.toLowerCase();
    return message.contains('no such file or directory') ||
        message.contains('cannot find the file') ||
        message.contains('not found');
  }
}

class _MediaConversionCanceledException implements Exception {
  const _MediaConversionCanceledException();
}

extension on File {
  Future<void> deleteIfExists() async {
    if (await exists()) {
      await delete();
    }
  }
}
