import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videodownloader/source_parser/ios/x_public_video_resolver.dart';
import 'package:videodownloader/source_parser/source_parser_service.dart';
import 'package:videodownloader/source_parser/source_resource.dart';

void main() {
  test(
    'authenticated X media uses native session and rejects other hosts',
    () async {
      final parser = SourceParserService(
        useNativeDownloads: true,
        xSessionResolver: (page) async {
          expect(page.path, '/demo/status/123');
          return [
            'https://video.twimg.com/clip.mp4',
            'https://video.twimg.com/clip.mp4',
            'https://video.twimg.com.evil.example/clip.mp4',
            'http://video.twimg.com/insecure.mp4',
          ];
        },
        client: MockClient((_) async => fail('Must use authenticated session')),
      );
      addTearDown(parser.dispose);
      final result = await parser.parse('https://x.com/demo/status/123');
      expect(result.resources.single.url, 'https://video.twimg.com/clip.mp4');
      expect(result.resources.single.requiresYtDlp, isFalse);
    },
  );

  final failures = <Object, String>{
    TimeoutException('request'): '超时',
    const SocketException('network'): '无法连接',
    const FormatException('bad json'): '无法识别',
    PlatformException(code: 'login_required', message: '请先登录 X'): '请先登录 X',
  };
  for (final entry in failures.entries) {
    test(
      'X session ${entry.key.runtimeType} becomes a visible parse failure',
      () async {
        final parser = SourceParserService(
          useNativeDownloads: true,
          xSessionResolver: (_) async => throw entry.key,
        );
        addTearDown(parser.dispose);
        await expectLater(
          parser.parse('https://x.com/demo/status/123'),
          throwsA(
            isA<SourceParserException>().having(
              (e) => e.message,
              'message',
              contains(entry.value),
            ),
          ),
        );
      },
    );
  }

  test(
    'public request timeout is converted instead of escaping UI catch',
    () async {
      final parser = SourceParserService(
        useNativeDownloads: true,
        xSessionResolver: (_) async => null,
        xPublicVideoResolver: XPublicVideoResolver(
          tokenGenerator: (_) async => 'token',
          requestTimeout: const Duration(milliseconds: 10),
        ),
        client: MockClient((_) => Completer<http.Response>().future),
      );
      addTearDown(parser.dispose);
      await expectLater(
        parser.parse('https://x.com/demo/status/123'),
        throwsA(
          isA<SourceParserException>().having(
            (e) => e.message,
            'message',
            contains('超时'),
          ),
        ),
      );
    },
  );
}
