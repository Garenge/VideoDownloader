import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class XLoginBridge {
  XLoginBridge._();

  static const MethodChannel _channel = MethodChannel(
    'videodownloader/x_login',
  );

  static Future<bool> openLogin() async {
    return await _channel.invokeMethod<bool>('login') ?? false;
  }

  static Future<bool?> isAuthenticated() async {
    try {
      return await _channel.invokeMethod<bool>('isAuthenticated');
    } on MissingPluginException {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> accountStatus() async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>('accountStatus');
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> logout() async {
    await _channel.invokeMethod<void>('logout');
  }

  static Future<void> configureIosProxy(String? spec) async {
    if (!Platform.isIOS) return;
    await _channel.invokeMethod<void>('configureProxy', spec);
  }

  static Future<List<String>?> resolveIosVideo(Uri page) async {
    if (!Platform.isIOS || await isAuthenticated() != true) return null;
    return await _channel.invokeListMethod<String>(
      'resolveVideo',
      page.toString(),
    );
  }

  static Future<T?> withCookieFile<T>(
    Future<T> Function(String cookieFilePath) action,
  ) async {
    String? cookieText;
    try {
      cookieText = await _channel.invokeMethod<String>('exportCookies');
    } on MissingPluginException {
      return null;
    } on FlutterError {
      return null;
    }
    final hasCookie = cookieText
        ?.split('\n')
        .any(
          (line) =>
              line.startsWith('#HttpOnly_') ||
              (line.isNotEmpty && !line.startsWith('#')),
        );
    if (cookieText == null || hasCookie != true) {
      return null;
    }

    final directory = await Directory.systemTemp.createTemp(
      'videodownloader-x-',
    );
    final cookieFile = File('${directory.path}/cookies.txt');
    try {
      await cookieFile.create(exclusive: true);
      await cookieFile.writeAsString(cookieText, flush: true);
      return await action(cookieFile.path);
    } finally {
      await directory.delete(recursive: true);
    }
  }
}
