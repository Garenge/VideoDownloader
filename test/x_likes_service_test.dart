import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/x_likes_service.dart';
import 'fixtures/x_likes_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('videodownloader/x_login');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('passes pagination cursor to native bridge', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'fetchLikes');
      expect(call.arguments, {'cursor': 'next'});
      return likesEnvelope(likesFixture([likedEntry('123')]));
    });
    expect(
      (await XLikesService().fetchLikes(cursor: 'next')).posts.single.id,
      '123',
    );
  });
  test('reports rate limiting and expired login', () async {
    for (final status in [401, 403, 429, 500]) {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => likesEnvelope('{}', status: status),
      );
      await expectLater(
        XLikesService().fetchLikes(),
        throwsA(isA<XLikesException>()),
      );
    }
  });
  test(
    'preserves native session expiry instruction for refresh retry',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async =>
            jsonEncode({'error': 'Session ended', 'requiresRefresh': true}),
      );
      await expectLater(
        XLikesService().fetchLikes(),
        throwsA(
          isA<XLikesException>().having(
            (e) => e.requiresRefresh,
            'requiresRefresh',
            isTrue,
          ),
        ),
      );
    },
  );
  test('disposing cancels native work and rejects later requests', () async {
    var canceled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      canceled = call.method == 'cancelLikes';
      return null;
    });
    final service = XLikesService()..dispose();
    await expectLater(service.fetchLikes(), throwsA(isA<XLikesException>()));
    expect(canceled, isTrue);
  });
}
