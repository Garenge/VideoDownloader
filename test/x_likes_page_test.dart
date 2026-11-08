import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/x_likes_page.dart';
import 'fixtures/x_likes_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('videodownloader/x_login');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  testWidgets(
    'pagination failure retains posts and retry merges unique posts',
    (tester) async {
      var requests = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'cancelLikes') return null;
        requests++;
        if (requests == 1) {
          return likesEnvelope(
            likesFixture([likedEntry('123')], cursor: 'next'),
          );
        }
        if (requests < 4) expect(call.arguments, {'cursor': 'next'});
        if (requests == 2) {
          throw PlatformException(code: 'offline', message: '网络不可用');
        }
        return likesEnvelope(
          likesFixture([likedEntry('123'), likedEntry('456')]),
        );
      });
      await tester.pumpWidget(const MaterialApp(home: XLikesPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('Post 123'), findsOneWidget);
      expect(find.text('网络不可用'), findsOneWidget);
      await tester.tap(find.text('重试加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('已加载 2 条'), findsOneWidget);
      expect(find.text('Post 123'), findsOneWidget);
      expect(find.text('Post 456'), findsOneWidget);
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(find.text('Post 123'), findsOneWidget);
    },
  );
  testWidgets('media action returns original post for parsing', (tester) async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'cancelLikes'
          ? null
          : likesEnvelope(likesFixture([likedEntry('123', media: true)])),
    );
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => const XLikesPage()),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('解析下载'));
    await tester.pumpAndSettle();
    expect(selected, 'https://x.com/i/status/123');
  });
}
