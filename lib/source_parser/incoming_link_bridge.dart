import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class IncomingLinkEvent {
  const IncomingLinkEvent({
    required this.sequence,
    required this.url,
    required this.source,
    this.origin = 'unknown',
    this.debugLog,
  });

  final int sequence;
  final String url;
  final String source;
  final String origin;
  final String? debugLog;

  bool get isFromShareExtension => origin == 'share_extension';
}

class IncomingLinkBridge {
  IncomingLinkBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'videodownloader/incoming_link';

  final MethodChannel _channel;
  final ValueNotifier<IncomingLinkEvent?> incomingLinkListenable =
      ValueNotifier<IncomingLinkEvent?>(null);

  int _eventSequence = 0;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);

    final initialEvent = await _loadInitialLink();
    if (initialEvent == null) {
      return;
    }

    _publishIncomingEvent(initialEvent);
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    incomingLinkListenable.dispose();
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method != 'onIncomingLink') {
      debugPrint(
        'lib/source_parser/incoming_link_bridge.dart#_handleMethodCall: '
        'ignored method=${call.method}',
      );
      return null;
    }

    final event = _eventFromChannelValue(call.arguments, source: 'live');
    if (event == null) {
      debugPrint(
        'lib/source_parser/incoming_link_bridge.dart#_handleMethodCall: '
        'ignored empty incoming link',
      );
      return null;
    }

    _publishIncomingEvent(event);
    return null;
  }

  Future<IncomingLinkEvent?> _loadInitialLink() async {
    try {
      final value = await _channel.invokeMethod<Object?>('getInitialLink');
      final event = _eventFromChannelValue(value, source: 'initial');
      if (event == null) {
        debugPrint(
          'lib/source_parser/incoming_link_bridge.dart#_loadInitialLink: '
          'no initial link',
        );
        return null;
      }

      debugPrint(
        'lib/source_parser/incoming_link_bridge.dart#_loadInitialLink: '
        'received initialUrl=${event.url} origin=${event.origin}',
      );
      return event;
    } on MissingPluginException {
      debugPrint(
        'lib/source_parser/incoming_link_bridge.dart#_loadInitialLink: '
        'channel unavailable on current platform',
      );
      return null;
    } on PlatformException catch (error) {
      debugPrint(
        'lib/source_parser/incoming_link_bridge.dart#_loadInitialLink: '
        'platform exception message=${error.message}',
      );
      return null;
    } on Object catch (error) {
      debugPrint(
        'lib/source_parser/incoming_link_bridge.dart#_loadInitialLink: '
        'unexpected error=$error',
      );
      return null;
    }
  }

  String? _normalizeUrl(Object? value) {
    final url = value?.toString().trim();
    if (url == null || url.isEmpty) {
      return null;
    }
    return url;
  }

  IncomingLinkEvent? _eventFromChannelValue(
    Object? value, {
    required String source,
  }) {
    final normalizedValue = _normalizePayloadValue(value);
    final url = _normalizeUrl(normalizedValue['url']);
    if (url == null) {
      return null;
    }

    return IncomingLinkEvent(
      sequence: _eventSequence + 1,
      url: url,
      source: source,
      origin: _normalizeString(normalizedValue['origin']) ?? 'unknown',
      debugLog: _normalizeString(normalizedValue['debugLog']),
    );
  }

  Map<String, Object?> _normalizePayloadValue(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
    }

    return <String, Object?>{'url': value};
  }

  String? _normalizeString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  void _publishIncomingEvent(IncomingLinkEvent event) {
    _eventSequence += 1;
    debugPrint(
      'lib/source_parser/incoming_link_bridge.dart#_publishIncomingUrl: '
      'sequence=$_eventSequence source=${event.source} origin=${event.origin} url=${event.url}',
    );
    incomingLinkListenable.value = IncomingLinkEvent(
      sequence: _eventSequence,
      url: event.url,
      source: event.source,
      origin: event.origin,
      debugLog: event.debugLog,
    );
  }
}
