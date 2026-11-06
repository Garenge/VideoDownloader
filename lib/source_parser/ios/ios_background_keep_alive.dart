import 'package:flutter/services.dart';

class IosBackgroundKeepAlive {
  const IosBackgroundKeepAlive();

  static const _channel = MethodChannel(
    'videodownloader/ios_background_keep_alive',
  );

  Future<void> start() async {
    await _channel.invokeMethod<void>('start');
  }

  Future<void> stop() async {
    await _channel.invokeMethod<void>('stop');
  }
}
