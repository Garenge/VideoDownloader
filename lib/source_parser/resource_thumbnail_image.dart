import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 使用 [http.Client] 拉取图片字节并显示缩略图（与 [ResourceHttpClientScope] 共用客户端，可走应用代理）。
class ResourceThumbnailImage extends StatefulWidget {
  const ResourceThumbnailImage({
    super.key,
    required this.imageUrl,
    required this.headers,
    required this.httpClient,
    this.fit = BoxFit.cover,
    this.placeholderColor,
    this.errorWidget,
    this.loadingWidget,
    this.timeout = const Duration(seconds: 15),
  });

  final String imageUrl;
  final Map<String, String> headers;
  final http.Client httpClient;

  /// 目标区域缩放方式。
  final BoxFit fit;

  final Color? placeholderColor;

  /// 占位层（可选）；默认小进度圈。
  final Widget? loadingWidget;

  /// 失败时兜底（可选）；默认 [Icons.image_outline]。
  final Widget? errorWidget;

  final Duration timeout;

  @override
  State<ResourceThumbnailImage> createState() => _ResourceThumbnailImageState();
}

class _ResourceThumbnailImageState extends State<ResourceThumbnailImage> {
  Uint8List? _bytes;
  bool _busy = true;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ResourceThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        !mapEquals(oldWidget.headers, widget.headers) ||
        !identical(oldWidget.httpClient, widget.httpClient)) {
      _load();
    }
  }

  Future<void> _load() async {
    final uri = Uri.tryParse(widget.imageUrl);
    if (uri == null || !uri.hasScheme) {
      if (mounted) {
        setState(() {
          _bytes = null;
          _busy = false;
        });
      }
      return;
    }

    _requestId += 1;
    final requestId = _requestId;

    if (mounted) {
      setState(() {
        _busy = true;
        _bytes = null;
      });
    }

    try {
      final response = await widget.httpClient
          .get(uri, headers: widget.headers)
          .timeout(widget.timeout);

      if (!mounted || requestId != _requestId) {
        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw StateError('HTTP ${response.statusCode}');
      }

      final body = response.bodyBytes;
      if (!mounted || requestId != _requestId) {
        return;
      }

      setState(() {
        _bytes = body;
        _busy = false;
      });
    } on Object {
      if (!mounted || requestId != _requestId) {
        return;
      }

      setState(() {
        _bytes = null;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy && _bytes == null) {
      final color =
          widget.placeholderColor ?? Theme.of(context).colorScheme.surface;
      return ColoredBox(
        color: color,
        child: Center(
          child:
              widget.loadingWidget ??
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
        ),
      );
    }

    if (_bytes == null || _bytes!.isEmpty) {
      return ColoredBox(
        color:
            widget.placeholderColor ??
            Theme.of(context).colorScheme.secondaryContainer,
        child: Center(child: widget.errorWidget ?? const Icon(Icons.image)),
      );
    }

    return Image.memory(
      _bytes!,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (context, Object error, StackTrace? trace) {
        return ColoredBox(
          color:
              widget.placeholderColor ??
              Theme.of(context).colorScheme.secondaryContainer,
          child: Center(
            child: widget.errorWidget ?? const Icon(Icons.broken_image),
          ),
        );
      },
    );
  }
}
