import 'package:flutter_test/flutter_test.dart';
import 'package:videodownloader/source_parser/proxied_http_client_factory.dart';

void main() {
  test('parseProxyUri adds scheme and parses host port', () {
    final uri = ProxiedHttpClientFactory.parseProxyUri('127.0.0.1:7890');
    expect(uri.scheme, 'http');
    expect(uri.host, '127.0.0.1');
    expect(uri.port, 7890);
  });

  test('parseProxyUri keeps explicit scheme', () {
    final uri = ProxiedHttpClientFactory.parseProxyUri('http://proxy.example:3128');
    expect(uri.host, 'proxy.example');
    expect(uri.port, 3128);
  });

  test('parseProxyUri decodes user info', () {
    final uri = ProxiedHttpClientFactory.parseProxyUri(
      'http://user%40x:p%40ss@10.0.0.1:8888',
    );
    expect(uri.userInfo, isNotEmpty);
    expect(uri.host, '10.0.0.1');
    expect(uri.port, 8888);
  });

  test('parseProxyUri throws when host missing', () {
    expect(
      () => ProxiedHttpClientFactory.parseProxyUri('http://'),
      throwsFormatException,
    );
  });
}
