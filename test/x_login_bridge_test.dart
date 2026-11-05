import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/x_login_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('videodownloader/x_login');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'passes cookies through a temporary file and deletes it afterward',
    () async {
      const cookieText =
          '# Netscape HTTP Cookie File\n.x.com\tTRUE\t/\tTRUE\t0\tauth_token\ttest-value\n';
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'exportCookies');
        return cookieText;
      });

      String? cookieFilePath;
      final result = await XLoginBridge.withCookieFile((path) async {
        cookieFilePath = path;
        expect(await File(path).readAsString(), cookieText);
        return 'ok';
      });

      expect(result, 'ok');
      expect(cookieFilePath, isNotNull);
      expect(await File(cookieFilePath!).exists(), isFalse);
      expect(
        await Directory(File(cookieFilePath!).parent.path).exists(),
        isFalse,
      );
    },
  );

  test('returns null when no X cookies are available', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return '# Netscape HTTP Cookie File\n# Generated temporarily\n';
    });

    final result = await XLoginBridge.withCookieFile((_) async => 'unexpected');

    expect(result, isNull);
  });

  test('reports persisted X login state through the native bridge', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isAuthenticated');
      return true;
    });

    expect(await XLoginBridge.isAuthenticated(), isTrue);
  });

  test('reads account status for the account menu', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'accountStatus');
      return <String, Object>{
        'authenticated': true,
        'handle': '@example',
        'displayName': 'Example User',
      };
    });

    expect(await XLoginBridge.accountStatus(), {
      'authenticated': true,
      'handle': '@example',
      'displayName': 'Example User',
    });
  });

  test('requests native logout', () async {
    var logoutCalled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'logout');
      logoutCalled = true;
      return null;
    });

    await XLoginBridge.logout();

    expect(logoutCalled, isTrue);
  });

  test('requests public X token through the desktop bridge', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'xToken');
      expect(call.arguments, '123');
      return 'test-token';
    });
    expect(await XLoginBridge.publicMediaToken('123'), 'test-token');
  });

  test('returns null when the native login bridge is unavailable', () async {
    expect(await XLoginBridge.isAuthenticated(), isNull);
  });
}
