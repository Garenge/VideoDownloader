import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 将与解析共用、含代理配置的 [http.Client] 下到子树（缩略图等需与解析同源网络栈）。
class ResourceHttpClientScope extends InheritedWidget {
  const ResourceHttpClientScope({
    super.key,
    required this.client,
    required super.child,
  });

  final http.Client client;

  static ResourceHttpClientScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ResourceHttpClientScope>();
  }

  static http.Client clientOf(BuildContext context) {
    final scope = maybeOf(context);
    if (scope == null) {
      throw FlutterError(
        'ResourceHttpClientScope not found: wrap the subtree with '
        'ResourceHttpClientScope(client: ..., child: ...) before showing '
        'resource thumbnails.',
      );
    }

    return scope.client;
  }

  @override
  bool updateShouldNotify(ResourceHttpClientScope oldWidget) {
    return !identical(oldWidget.client, client);
  }
}
