import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videodownloader/source_parser/download_queue_controller.dart';
import 'package:videodownloader/source_parser/resumable_file_transfer.dart';

void main() {
  late Directory directory;
  late File partial;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('resume-transfer-');
    partial = File('${directory.path}/video.part');
    await partial.writeAsString('abc');
  });
  tearDown(() => directory.delete(recursive: true));

  Future<void> transfer(http.Client client) => ResumableFileTransfer(
    client: client,
    isCanceled: () => false,
    onProgress: (_, _) {},
  ).download(Uri.parse('https://example.com/video'), partial);

  test(
    'requests persisted length and validator and appends a valid 206',
    () async {
      await File(
        '${partial.path}.json',
      ).writeAsString('{"validator":"\\\"v1\\\""}');
      await transfer(
        MockClient((request) async {
          expect(request.headers['Range'], 'bytes=3-');
          expect(request.headers['If-Range'], '"v1"');
          return http.Response(
            'def',
            206,
            headers: {'content-range': 'bytes 3-5/6', 'etag': '"v1"'},
          );
        }),
      );
      expect(await partial.readAsString(), 'abcdef');
    },
  );

  test(
    'server ignoring Range replaces old bytes with a complete 200',
    () async {
      await transfer(
        MockClient((_) async => http.Response('replacement', 200)),
      );
      expect(await partial.readAsString(), 'replacement');
    },
  );

  test('416 restarts with a request without Range', () async {
    var calls = 0;
    await transfer(
      MockClient((request) async {
        if (calls++ == 0) return http.Response('', 416);
        expect(request.headers.containsKey('Range'), isFalse);
        return http.Response('new', 200);
      }),
    );
    expect(calls, 2);
    expect(await partial.readAsString(), 'new');
  });

  test('rejects invalid ranges without appending bytes', () async {
    await expectLater(
      transfer(
        MockClient(
          (_) async => http.Response(
            'bad',
            206,
            headers: {'content-range': 'bytes 2-4/5'},
          ),
        ),
      ),
      throwsA(isA<DownloadException>()),
    );
    expect(await partial.readAsString(), 'abc');
  });

  test(
    'retains partial data after a network failure for the next request',
    () async {
      final client = MockClient.streaming(
        (request, _) async => http.StreamedResponse(
          Stream<List<int>>.error(const SocketException('network lost')),
          206,
          headers: {'content-range': 'bytes 3-5/6'},
        ),
      );
      await expectLater(transfer(client), throwsA(isA<SocketException>()));
      expect(await partial.readAsString(), 'abc');
      await transfer(
        MockClient(
          (_) async => http.Response(
            'def',
            206,
            headers: {'content-range': 'bytes 3-5/6'},
          ),
        ),
      );
      expect(await partial.readAsString(), 'abcdef');
    },
  );

  test('rejects a truncated response and preserves received bytes', () async {
    final client = MockClient.streaming(
      (_, _) async => http.StreamedResponse(
        Stream.value('de'.codeUnits),
        206,
        headers: {'content-range': 'bytes 3-5/6'},
      ),
    );
    await expectLater(transfer(client), throwsA(isA<DownloadException>()));
    expect(await partial.readAsString(), 'abcde');
  });

  test('cancels while an otherwise idle stream is waiting', () async {
    var canceled = false;
    final stream = StreamController<List<int>>();
    final client = MockClient.streaming(
      (_, _) async => http.StreamedResponse(
        stream.stream,
        206,
        headers: {'content-range': 'bytes 3-5/6'},
      ),
    );
    final future = ResumableFileTransfer(
      client: client,
      isCanceled: () => canceled,
      onProgress: (_, _) {},
    ).download(Uri.parse('https://example.com/video'), partial);
    final expectation = expectLater(
      future,
      throwsA(isA<DownloadCanceledException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    canceled = true;
    await expectation.timeout(const Duration(seconds: 2));
    await stream.close();
    expect(await partial.readAsString(), 'abc');
  });
}
