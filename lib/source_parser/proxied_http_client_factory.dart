import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Builds [http.Client] with optional HTTP 代理（基于 dart:io [HttpClient]）。
class ProxiedHttpClientFactory {
  static http.Client create(String? proxySpec) {
    final spec = proxySpec?.trim();
    if (spec == null || spec.isEmpty) {
      return http.Client();
    }

    final proxyUri = parseProxyUri(spec);
    final host = proxyUri.host;
    if (host.isEmpty) {
      return http.Client();
    }

    final port = proxyUri.hasPort && proxyUri.port != 0
        ? proxyUri.port
        : 8080;

    final ioClient = HttpClient();
    ioClient.findProxy = (_) => 'PROXY $host:$port';

    final userInfo = proxyUri.userInfo;
    if (userInfo.isNotEmpty) {
      final separatorIndex = userInfo.indexOf(':');
      final user = separatorIndex >= 0
          ? Uri.decodeComponent(userInfo.substring(0, separatorIndex))
          : Uri.decodeComponent(userInfo);
      final password = separatorIndex >= 0
          ? Uri.decodeComponent(userInfo.substring(separatorIndex + 1))
          : '';
      ioClient.addProxyCredentials(
        host,
        port,
        '',
        HttpClientBasicCredentials(user, password),
      );
    }

    return IOClient(ioClient);
  }

  /// 支持 `http://host:port`、`host:port`、`http://user:pass@host:port`。
  static Uri parseProxyUri(String raw) {
    var input = raw.trim();
    if (input.isEmpty) {
      return Uri();
    }

    if (!input.contains('://')) {
      input = 'http://$input';
    }

    final uri = Uri.parse(input);
    if (uri.host.isEmpty) {
      throw const FormatException('代理地址缺少主机名');
    }

    return uri;
  }

  /// 通过代理发起短请求，用于连通性检测。
  static Future<String> testProxy(String proxySpec) async {
    final client = create(proxySpec);
    try {
      final uri = Uri.parse('https://www.gstatic.com/generate_204');
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode >= 200 && response.statusCode < 400) {
        return 'HTTP ${response.statusCode}';
      }

      throw StateError('HTTP ${response.statusCode}');
    } on TimeoutException {
      throw StateError('请求超时');
    } finally {
      client.close();
    }
  }
}
