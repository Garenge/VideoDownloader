import 'package:flutter/material.dart';

import 'download_settings.dart';

typedef DownloadSettingsApplyCallback =
    Future<void> Function(DownloadSettings settings);

Future<void> showDownloadSettingsDialog({
  required BuildContext context,
  required DownloadSettings initialSettings,
  required DownloadToolStatus toolStatus,
  required DownloadSettingsApplyCallback onApply,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return _DownloadSettingsDialog(
        initialSettings: initialSettings,
        toolStatus: toolStatus,
        onApply: onApply,
      );
    },
  );
}

class _DownloadSettingsDialog extends StatefulWidget {
  const _DownloadSettingsDialog({
    required this.initialSettings,
    required this.toolStatus,
    required this.onApply,
  });

  final DownloadSettings initialSettings;
  final DownloadToolStatus toolStatus;
  final DownloadSettingsApplyCallback onApply;

  @override
  State<_DownloadSettingsDialog> createState() =>
      _DownloadSettingsDialogState();
}

class _DownloadSettingsDialogState extends State<_DownloadSettingsDialog> {
  late bool _enableYtDlpFallback;
  late bool _preferYtDlpForYouTube;
  late final TextEditingController _concurrencyController;
  late final TextEditingController _retriesController;
  late final TextEditingController _fragmentRetriesController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final settings = widget.initialSettings;
    _enableYtDlpFallback = settings.enableYtDlpFallback;
    _preferYtDlpForYouTube = settings.preferYtDlpForYouTube;
    _concurrencyController = TextEditingController(
      text: settings.ytDlpConcurrency.toString(),
    );
    _retriesController = TextEditingController(
      text: settings.ytDlpRetries.toString(),
    );
    _fragmentRetriesController = TextEditingController(
      text: settings.ytDlpFragmentRetries.toString(),
    );
  }

  @override
  void dispose() {
    _concurrencyController.dispose();
    _retriesController.dispose();
    _fragmentRetriesController.dispose();
    super.dispose();
  }

  int? _readPositiveInt(String value, {required int min, required int max}) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      return null;
    }
    if (parsed < min || parsed > max) {
      return null;
    }
    return parsed;
  }

  Future<void> _handleSave() async {
    final concurrency = _readPositiveInt(
      _concurrencyController.text,
      min: 1,
      max: 32,
    );
    final retries = _readPositiveInt(_retriesController.text, min: 0, max: 50);
    final fragmentRetries = _readPositiveInt(
      _fragmentRetriesController.text,
      min: 0,
      max: 200,
    );

    if (concurrency == null || retries == null || fragmentRetries == null) {
      setState(() {
        _errorText = '参数格式不正确：并发(1-32)，重试(0-50)，分片重试(0-200)';
      });
      return;
    }

    if (_enableYtDlpFallback && !widget.toolStatus.ytDlpAvailable) {
      setState(() {
        _errorText = '当前系统未检测到 yt-dlp，开启兜底可能仍会失败';
      });
      // 允许保存，让用户先开关，后续安装后生效
    }

    final settings = DownloadSettings(
      enableYtDlpFallback: _enableYtDlpFallback,
      preferYtDlpForYouTube: _enableYtDlpFallback
          ? _preferYtDlpForYouTube
          : false,
      ytDlpConcurrency: concurrency,
      ytDlpRetries: retries,
      ytDlpFragmentRetries: fragmentRetries,
    );

    await widget.onApply(settings);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final toolStatus = widget.toolStatus;
    final ytDlpLabel = toolStatus.ytDlpAvailable
        ? '已检测到${toolStatus.ytDlpVersion == null ? '' : ' (${toolStatus.ytDlpVersion})'}'
        : '未检测到';
    final ffmpegLabel = toolStatus.ffmpegAvailable
        ? '已检测到${toolStatus.ffmpegVersion == null ? '' : ' (${toolStatus.ffmpegVersion})'}'
        : '未检测到';

    return AlertDialog(
      title: const Text('下载设置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '工具状态：yt-dlp $ytDlpLabel，ffmpeg $ffmpegLabel',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (toolStatus.externalCommandBlocked) ...[
              const SizedBox(height: 6),
              Text(
                '检测到外部命令执行受限（可能是 macOS 沙箱限制）',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'X 推文下载依赖 yt-dlp；下方参数也会复用到 YouTube 的 yt-dlp 流程。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用 YouTube 应用内回退'),
              subtitle: const Text(
                '在 built-in priority 模式下自动切换到 youtube_explode_dart',
              ),
              value: _enableYtDlpFallback,
              onChanged: (value) {
                setState(() {
                  _enableYtDlpFallback = value;
                  if (!value) {
                    _preferYtDlpForYouTube = false;
                  }
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('YouTube 优先使用 yt-dlp'),
              subtitle: const Text('使用独立下载流程；失败时直接返回明确错误'),
              value: _enableYtDlpFallback && _preferYtDlpForYouTube,
              onChanged: _enableYtDlpFallback
                  ? (value) {
                      setState(() {
                        _preferYtDlpForYouTube = value;
                      });
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _concurrencyController,
                    decoration: const InputDecoration(
                      labelText: 'yt-dlp 并发 (-N)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _retriesController,
                    decoration: const InputDecoration(
                      labelText: '重试 (--retries)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fragmentRetriesController,
              decoration: const InputDecoration(
                labelText: '分片重试 (--fragment-retries)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _handleSave, child: const Text('保存')),
      ],
    );
  }
}
