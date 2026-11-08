import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'x_likes_models.dart';
import 'x_likes_parser.dart';
import 'x_login_bridge.dart';

export 'x_likes_models.dart';

class XLikesService {
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    unawaited(XLoginBridge.cancelLikes());
  }

  Future<XLikesResponse> fetchLikes({String? cursor}) async {
    if (_disposed) throw const XLikesException('点赞页面已关闭');
    try {
      final envelope =
          jsonDecode(
                await XLoginBridge.fetchLikesJson(
                  cursor: cursor,
                ).timeout(const Duration(seconds: 35)),
              )
              as Map<String, dynamic>;
      if (envelope['error'] is String) {
        throw XLikesException(
          envelope['error'] as String,
          requiresRefresh: envelope['requiresRefresh'] == true,
        );
      }
      final status = envelope['statusCode'] as int? ?? 0;
      if (status != 200) throw XLikesException(_statusMessage(status));
      final raw = envelope['rawJson'] as String?;
      if (raw == null) throw const XLikesException('X 点赞响应缺少数据');
      return parseXLikesResponse(
        raw,
        endpoint: Uri.parse(envelope['endpoint'] as String),
        requestedCursor: cursor,
      );
    } on TimeoutException {
      await XLoginBridge.cancelLikes();
      throw const XLikesException('X 点赞请求超时，请重试', requiresRefresh: true);
    } on PlatformException catch (error) {
      throw XLikesException(error.message ?? 'X 点赞读取失败');
    } on FormatException {
      throw const XLikesException('X 点赞响应格式异常，请重试');
    } on TypeError {
      throw const XLikesException('X 点赞响应格式异常，请重试');
    }
  }

  String _statusMessage(int status) => switch (status) {
    401 || 403 => 'X 登录已失效或无权读取，请在设置中重新登录',
    429 => 'X 请求过于频繁，请稍后重试',
    _ => 'X 点赞请求失败（HTTP $status），请重试',
  };
}

class XLikesException implements Exception {
  const XLikesException(this.message, {this.requiresRefresh = false});
  final String message;
  final bool requiresRefresh;
  @override
  String toString() => message;
}
