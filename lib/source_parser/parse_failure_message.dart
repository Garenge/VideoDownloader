import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'source_resource.dart';

String parseFailureMessage(Object error) {
  if (error is SourceParserException) return error.message;
  if (error is TimeoutException) {
    return '解析请求超时，请检查网络或应用内代理后重试；登录无法解决网络连接超时。';
  }
  if (error is SocketException || error is http.ClientException) {
    return '无法连接网站，请检查网络或应用内代理后重试。';
  }
  if (error is HandshakeException) return '网站安全连接失败，请检查网络或代理后重试。';
  if (error is FormatException) return '网站返回了无法识别的数据，请稍后重试。';
  if (error is PlatformException) return error.message ?? 'iOS 解析模块异常，请重试。';
  return '解析失败，请重试或更换链接；详细原因已记录到调试日志。';
}
