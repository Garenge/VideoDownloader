import 'package:flutter/material.dart';

import 'proxied_http_client_factory.dart';

typedef ProxySettingsApplyCallback = Future<void> Function(String? proxySpec);

Future<void> showProxySettingsDialog({
  required BuildContext context,
  required String? initialProxySpec,
  required ProxySettingsApplyCallback onApply,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return _ProxySettingsDialog(
        initialProxySpec: initialProxySpec,
        onApply: onApply,
      );
    },
  );
}

class _ProxySettingsDialog extends StatefulWidget {
  const _ProxySettingsDialog({
    required this.initialProxySpec,
    required this.onApply,
  });

  final String? initialProxySpec;
  final ProxySettingsApplyCallback onApply;

  @override
  State<_ProxySettingsDialog> createState() => _ProxySettingsDialogState();
}

class _ProxySettingsDialogState extends State<_ProxySettingsDialog> {
  late final TextEditingController _controller;
  bool _isTesting = false;
  String? _testMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialProxySpec ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final raw = _controller.text.trim();
    if (raw.isNotEmpty) {
      try {
        ProxiedHttpClientFactory.parseProxyUri(raw);
      } on FormatException catch (error) {
        setState(() {
          _testMessage = error.message;
        });
        return;
      }
    }

    await widget.onApply(raw.isEmpty ? null : raw);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleClear() async {
    _controller.clear();
    setState(() {
      _testMessage = null;
    });
    await widget.onApply(null);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleTest() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _testMessage = '请先填写代理地址';
      });
      return;
    }

    try {
      ProxiedHttpClientFactory.parseProxyUri(raw);
    } on FormatException catch (error) {
      setState(() {
        _testMessage = error.message;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testMessage = null;
    });

    try {
      final detail = await ProxiedHttpClientFactory.testProxy(raw);
      if (!mounted) {
        return;
      }

      setState(() {
        _testMessage = '测试成功（$detail）';
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _testMessage = 'lib/source_parser/proxy_settings_sheet.dart#_handleTest: 测试失败: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('网络代理'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('proxy-spec-field'),
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'HTTP 代理',
                hintText: '127.0.0.1:7890 或 http://user:pass@host:8080',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            if (_testMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _testMessage!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _testMessage!.contains('测试成功')
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isTesting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _isTesting ? null : _handleClear,
          child: const Text('清空并保存'),
        ),
        FilledButton.tonal(
          onPressed: _isTesting ? null : _handleTest,
          child: _isTesting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('测试'),
        ),
        FilledButton(
          onPressed: _isTesting ? null : _handleSave,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
