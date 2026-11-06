import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'download_queue_controller.dart';

/// A file's actual length, rather than a saved progress counter, is the offset.
class ResumableFileTransfer {
  ResumableFileTransfer({
    required this.client,
    required this.isCanceled,
    required this.onProgress,
  });

  final http.Client client;
  final bool Function() isCanceled;
  final void Function(int received, int? total) onProgress;

  Future<File> download(Uri uri, File partial, {int? expectedBytes}) async {
    await partial.parent.create(recursive: true);
    var offset = await partial.exists() ? await partial.length() : 0;
    final validator = await _readValidator(partial);
    var response = await _request(uri, offset, validator);
    // A 416 response is not sufficient proof that local bytes are complete.
    if (response.statusCode == 416 && offset > 0) {
      await response.stream.drain<void>();
      offset = 0;
      response = await _request(uri, 0, null);
    }
    final total = _responseTotal(response, offset, expectedBytes);
    final append = response.statusCode == 206 && offset > 0;
    if (!append) {
      offset = 0;
      await partial.writeAsBytes([], flush: true);
    }
    _validateRepresentation(response, append ? validator : null);
    await _saveValidator(partial, response, append ? validator : null);
    await _receive(response, partial, offset, total, append);
    return partial;
  }

  Future<http.StreamedResponse> _request(
    Uri uri,
    int offset,
    String? validator,
  ) {
    final request = http.Request('GET', uri);
    request.headers.addAll({
      'User-Agent': 'VideoDownloader/1.0',
      'Accept-Encoding': 'identity',
      if (offset > 0) 'Range': 'bytes=$offset-',
      if (offset > 0 && validator != null) 'If-Range': validator,
    });
    return _wait(client.send(request));
  }

  int? _responseTotal(
    http.StreamedResponse response,
    int offset,
    int? expected,
  ) {
    if (response.statusCode == 206) {
      final range = RegExp(
        r'^bytes (\d+)-(\d+)/(\d+)$',
      ).firstMatch(response.headers['content-range'] ?? '');
      if (range == null ||
          int.parse(range[1]!) != offset ||
          int.parse(range[2]!) < offset ||
          int.parse(range[2]!) >= int.parse(range[3]!)) {
        throw const DownloadException('服务器返回的续传范围无效，请重试');
      }
      final total = int.parse(range[3]!);
      if (expected != null && expected != total) {
        throw const DownloadException('媒体大小已变化，请重新解析下载');
      }
      return total;
    }
    if (response.statusCode != 200) {
      throw DownloadException('HTTP ${response.statusCode}');
    }
    return expected ?? response.contentLength;
  }

  Future<void> _receive(
    http.StreamedResponse response,
    File partial,
    int offset,
    int? total,
    bool append,
  ) async {
    final iterator = StreamIterator(response.stream);
    final sink = partial.openWrite(
      mode: append ? FileMode.append : FileMode.write,
    );
    var received = offset;
    onProgress(received, total);
    try {
      while (await _wait(iterator.moveNext())) {
        sink.add(iterator.current);
        received += iterator.current.length;
        onProgress(received, total);
      }
      await sink.flush();
    } finally {
      await iterator.cancel();
      await sink.close();
    }
    if (received == 0) {
      throw const DownloadException('下载结果为空文件，已判定为失败；请重试');
    }
    if (total != null && received != total) {
      throw const DownloadException('下载数据不完整，已保留进度，可重试续传');
    }
  }

  Future<T> _wait<T>(Future<T> future) async {
    final canceled = Completer<T>();
    final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (isCanceled() && !canceled.isCompleted) {
        canceled.completeError(const DownloadCanceledException());
      }
    });
    try {
      if (isCanceled()) throw const DownloadCanceledException();
      return await Future.any([
        future.timeout(const Duration(minutes: 2)),
        canceled.future,
      ]);
    } finally {
      timer.cancel();
    }
  }

  Future<String?> _readValidator(File partial) async {
    try {
      final json = jsonDecode(await _metadataFile(partial).readAsString());
      return json['validator'] as String?;
    } on Object {
      return null;
    }
  }

  String? _validator(http.StreamedResponse response) {
    final etag = response.headers['etag'];
    return etag != null && !etag.startsWith('W/')
        ? etag
        : response.headers['last-modified'];
  }

  void _validateRepresentation(
    http.StreamedResponse response,
    String? previous,
  ) {
    final encoding = response.headers['content-encoding'];
    if (encoding != null && encoding != 'identity') {
      throw const DownloadException('服务器返回了压缩数据，无法安全续传');
    }
    final current = _validator(response);
    if (previous != null && current != null && previous != current) {
      throw const DownloadException('资源已变化，服务器未正确处理续传请求');
    }
  }

  Future<void> _saveValidator(
    File partial,
    http.StreamedResponse response,
    String? previous,
  ) async {
    final file = _metadataFile(partial);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'validator': _validator(response) ?? previous}),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  static File _metadataFile(File partial) =>
      File('${partial.parent.path}/.${partial.uri.pathSegments.last}.json');

  static Future<void> deletePartial(File partial) async {
    for (final file in [partial, _metadataFile(partial)]) {
      if (await file.exists()) await file.delete();
    }
  }
}
