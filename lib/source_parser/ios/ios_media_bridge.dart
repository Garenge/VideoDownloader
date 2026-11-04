import 'dart:async';

import 'package:flutter/services.dart';

import '../download_queue_controller.dart';

class IosMediaBridge {
  const IosMediaBridge();

  static const channel = MethodChannel('videodownloader/ios_media');

  Future<String> xToken(String statusId) async {
    final token = await channel.invokeMethod<String>('xToken', statusId);
    if (token == null || token.isEmpty) {
      throw const SourceTokenException();
    }
    return token;
  }

  Future<void> exportFile(String path) =>
      channel.invokeMethod<void>('exportFile', path);

  Future<void> merge({
    required String id,
    required String videoPath,
    required String audioPath,
    required String outputPath,
    required bool Function() isCanceled,
  }) async {
    final timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (isCanceled()) {
        unawaited(channel.invokeMethod<void>('cancelMerge', id));
      }
    });
    try {
      await channel.invokeMethod<void>('merge', {
        'id': id,
        'videoPath': videoPath,
        'audioPath': audioPath,
        'outputPath': outputPath,
      });
      if (isCanceled()) {
        throw const DownloadCanceledException();
      }
    } on PlatformException catch (error) {
      if (isCanceled()) {
        throw const DownloadCanceledException();
      }
      throw DownloadException(error.message ?? 'iOS 音视频合并失败');
    } finally {
      timer.cancel();
    }
  }
}

class SourceTokenException implements Exception {
  const SourceTokenException();

  @override
  String toString() => 'iOS 平台解析模块未就绪，请重新启动 App';
}
