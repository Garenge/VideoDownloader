import 'package:flutter/material.dart';

import 'download_history_store.dart';
import 'download_queue_controller.dart';
import 'download_settings.dart';

class DownloadSettingsPanel extends StatelessWidget {
  const DownloadSettingsPanel({
    super.key,
    required this.selectedDirectoryPath,
    required this.downloadSettings,
    required this.toolStatus,
    required this.onSelectDirectory,
    required this.onResetDirectory,
    required this.onOpenDownloadSettings,
  });

  final String? selectedDirectoryPath;
  final DownloadSettings downloadSettings;
  final DownloadToolStatus toolStatus;
  final VoidCallback onSelectDirectory;
  final VoidCallback onResetDirectory;
  final VoidCallback onOpenDownloadSettings;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.folder_open, size: 20),
            const SizedBox(width: 10),
            Expanded(child: _buildDirectoryText(context)),
            const SizedBox(width: 10),
            _ToolChip(
              label: 'yt-dlp',
              ok: toolStatus.ytDlpAvailable,
              tooltip: toolStatus.ytDlpVersion,
            ),
            const SizedBox(width: 8),
            _ToolChip(
              label: 'ffmpeg',
              ok: toolStatus.ffmpegAvailable,
              tooltip: toolStatus.ffmpegVersion,
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onSelectDirectory,
              tooltip: '选择保存目录',
              icon: const Icon(Icons.drive_folder_upload),
            ),
            IconButton(
              onPressed: onOpenDownloadSettings,
              tooltip: '下载设置',
              icon: const Icon(Icons.tune),
            ),
            if (selectedDirectoryPath != null)
              IconButton(
                onPressed: onResetDirectory,
                tooltip: '重置为默认目录',
                icon: const Icon(Icons.restart_alt),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectoryText(BuildContext context) {
    final path = selectedDirectoryPath;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '下载设置',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          path ?? '默认保存到应用文档目录（VideoDownloader）',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          downloadSettings.enableYtDlpFallback
              ? downloadSettings.preferYtDlpForYouTube
                    ? 'YouTube 下载：yt-dlp 优先'
                    : 'YouTube 下载：应用内优先，yt-dlp 兜底'
              : 'YouTube 下载：仅应用内',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        if (toolStatus.externalCommandBlocked) ...[
          const SizedBox(height: 2),
          Text(
            '外部命令执行受限（沙箱）',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.label, required this.ok, this.tooltip});

  final String label;
  final bool ok;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final bg = ok
        ? Theme.of(context).colorScheme.secondaryContainer
        : Theme.of(context).colorScheme.errorContainer;
    final fg = ok
        ? Theme.of(context).colorScheme.onSecondaryContainer
        : Theme.of(context).colorScheme.onErrorContainer;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final detail = tooltip?.trim();
    if (detail == null || detail.isEmpty) {
      return content;
    }
    return Tooltip(message: detail, child: content);
  }
}

class DownloadQueuePanel extends StatelessWidget {
  const DownloadQueuePanel({
    super.key,
    required this.tasks,
    required this.onCancel,
    required this.onRetry,
    required this.onOpenFolder,
    required this.onCopyLogs,
  });

  final List<DownloadTask> tasks;
  final ValueChanged<DownloadTask> onCancel;
  final ValueChanged<DownloadTask> onRetry;
  final ValueChanged<DownloadTask> onOpenFolder;
  final ValueChanged<DownloadTask> onCopyLogs;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.download_for_offline, size: 20),
                const SizedBox(width: 8),
                Text(
                  '下载队列',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                _CountPill(label: '任务', count: tasks.length),
              ],
            ),
            const SizedBox(height: 10),
            for (final task in tasks) ...[
              _DownloadTaskTile(
                task: task,
                onCancel: () => onCancel(task),
                onRetry: () => onRetry(task),
                onOpenFolder: () => onOpenFolder(task),
                onCopyLogs: () => onCopyLogs(task),
              ),
              if (task != tasks.last) const Divider(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class DownloadHistoryPanel extends StatelessWidget {
  const DownloadHistoryPanel({
    super.key,
    required this.records,
    required this.onOpenFolder,
    required this.onConvertToMp4,
    required this.onClear,
  });

  final List<DownloadHistoryRecord> records;
  final ValueChanged<DownloadHistoryRecord> onOpenFolder;
  final ValueChanged<DownloadHistoryRecord> onConvertToMp4;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.history, size: 20),
                const SizedBox(width: 8),
                Text(
                  '下载历史',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton.icon(
                  key: const ValueKey('clear-download-history-button'),
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('清空'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final record in records) ...[
              _DownloadHistoryTile(
                record: record,
                onOpenFolder: () => onOpenFolder(record),
                onConvertToMp4: record.isM3u8
                    ? () => onConvertToMp4(record)
                    : null,
              ),
              if (record != records.last) const Divider(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class _DownloadHistoryTile extends StatelessWidget {
  const _DownloadHistoryTile({
    required this.record,
    required this.onOpenFolder,
    this.onConvertToMp4,
  });

  final DownloadHistoryRecord record;
  final VoidCallback onOpenFolder;
  final VoidCallback? onConvertToMp4;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DownloadStatusIcon(status: DownloadStatus.completed),
        const SizedBox(width: 12),
        Expanded(child: _buildRecordContent(context)),
        const SizedBox(width: 8),
        if (onConvertToMp4 != null)
          IconButton(
            onPressed: onConvertToMp4,
            tooltip: '转 MP4',
            icon: const Icon(Icons.movie_creation_outlined),
          ),
        if (onConvertToMp4 != null) const SizedBox(width: 4),
        IconButton(
          onPressed: onOpenFolder,
          tooltip: '打开所在文件夹',
          icon: const Icon(Icons.folder_open),
        ),
      ],
    );
  }

  Widget _buildRecordContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          record.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '完成于 ${_formatCompletedAt(record.completedAt)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          record.filePath,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _formatCompletedAt(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
  }
}

class _DownloadTaskTile extends StatelessWidget {
  const _DownloadTaskTile({
    required this.task,
    required this.onCancel,
    required this.onRetry,
    required this.onOpenFolder,
    required this.onCopyLogs,
  });

  final DownloadTask task;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onOpenFolder;
  final VoidCallback onCopyLogs;

  @override
  Widget build(BuildContext context) {
    final canCancel =
        task.status == DownloadStatus.pending ||
        task.status == DownloadStatus.downloading;
    final canRetry = task.status == DownloadStatus.failed;
    final canCopyLogs = task.logs.isNotEmpty;
    final canOpenFolder =
        task.status == DownloadStatus.completed && task.filePath != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DownloadStatusIcon(status: task.status),
          const SizedBox(width: 12),
          Expanded(child: _buildTaskContent(context)),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                if (canOpenFolder)
                  _TaskActionButton(
                    onPressed: onOpenFolder,
                    tooltip: '打开所在文件夹',
                    icon: Icons.folder_open,
                  ),
                if (canRetry)
                  _TaskActionButton(
                    onPressed: onRetry,
                    tooltip: '重试',
                    icon: Icons.refresh,
                  ),
                if (canCopyLogs)
                  _TaskActionButton(
                    onPressed: onCopyLogs,
                    tooltip: '复制日志',
                    icon: Icons.copy_all,
                  ),
                if (canCancel)
                  _TaskActionButton(
                    onPressed: onCancel,
                    tooltip: '取消',
                    icon: Icons.close,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                task.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _statusBadgeBackgroundColor(context, task.status),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                task.status.displayName,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: _statusBadgeForegroundColor(context, task.status),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: _progressIndicatorValue(task),
          minHeight: 6,
          borderRadius: BorderRadius.circular(6),
        ),
        const SizedBox(height: 6),
        _TaskMetaInfo(task: task),
      ],
    );
  }
}

class _TaskMetaInfo extends StatelessWidget {
  const _TaskMetaInfo({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final secondaryStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant);
    final emphasisStyle = secondaryStyle?.copyWith(
      fontWeight: FontWeight.w700,
      color: colorScheme.onSurface,
    );
    final leadingText = _leadingMetaText(task);
    final trailingText = _trailingMetaText(task);
    final detailText = _detailMetaText(task);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                leadingText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: emphasisStyle,
              ),
            ),
            if (trailingText.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                trailingText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: emphasisStyle,
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          detailText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: secondaryStyle,
        ),
      ],
    );
  }
}

String _leadingMetaText(DownloadTask task) {
  final elapsed = _formatDownloadElapsed(task.activeStartedAt);
  if (elapsed.isNotEmpty) {
    return elapsed;
  }

  return switch (task.status) {
    DownloadStatus.pending => '等待开始',
    DownloadStatus.downloading => '准备下载',
    DownloadStatus.completed => '已保存',
    DownloadStatus.failed => '下载失败',
    DownloadStatus.canceled => '已取消',
  };
}

String _trailingMetaText(DownloadTask task) {
  return switch (task.status) {
    DownloadStatus.pending => '排队中',
    DownloadStatus.completed => '100%',
    DownloadStatus.failed ||
    DownloadStatus.canceled => _compactProgressText(task),
    DownloadStatus.downloading => _compactProgressText(task),
  };
}

String _detailMetaText(DownloadTask task) {
  final error = task.errorMessage?.trim();
  if (error != null && error.isNotEmpty) {
    return error;
  }

  final filePath = task.filePath;
  if (filePath != null && task.status == DownloadStatus.completed) {
    return '保存到 ${_compactSavedLocation(filePath)}';
  }

  return switch (task.status) {
    DownloadStatus.pending => '等待前序任务完成后自动开始',
    DownloadStatus.downloading => _compactStatusText(task),
    DownloadStatus.completed => '下载完成',
    DownloadStatus.failed => '下载失败，请查看日志后重试',
    DownloadStatus.canceled => '任务已取消，可重新发起下载',
  };
}

String _compactProgressText(DownloadTask task) {
  final totalBytes = task.totalBytes;
  if (totalBytes != null && totalBytes > 0) {
    final percent = (task.progress * 100).clamp(0, 100).toStringAsFixed(0);
    return '$percent%';
  }

  if (task.receivedBytes > 0) {
    return _formatBytes(task.receivedBytes);
  }

  return '';
}

String _compactStatusText(DownloadTask task) {
  final detail = task.statusDetail?.trim() ?? '';
  final waitSeconds = _downloadElapsedSeconds(task.activeStartedAt);
  final totalBytes = task.totalBytes;

  if (detail.contains('解析可用清晰度')) {
    return '正在解析清晰度';
  }
  if (detail.contains('获取视频信息')) {
    return '正在获取视频信息';
  }
  if (detail.contains('正在下载视频流')) {
    return _downloadAmountLabel(task, fallback: '正在下载视频流');
  }
  if (detail.contains('改用 yt-dlp')) {
    return '正在切换到 yt-dlp';
  }
  if (detail.contains('yt-dlp 下载中')) {
    return _downloadAmountLabel(task, fallback: 'yt-dlp 下载中');
  }
  if (detail.contains('连接服务器')) {
    return waitSeconds > 0 ? '连接服务器中，已等待 ${waitSeconds}s' : '连接服务器中';
  }
  if (detail.contains('连接资源中')) {
    return waitSeconds > 0 ? '连接资源中，已等待 ${waitSeconds}s' : '连接资源中';
  }
  if (detail.contains('准备下载')) {
    return '准备下载';
  }
  if (detail.contains('已知文件大小') || totalBytes != null && totalBytes > 0) {
    return _downloadAmountLabel(task, fallback: '正在下载内容');
  }
  if (detail.contains('未提供总大小')) {
    return task.receivedBytes > 0
        ? '已接收 ${_formatBytes(task.receivedBytes)}'
        : '正在接收数据';
  }
  if (detail.isNotEmpty) {
    return _normalizeStatusDetail(detail);
  }
  if (task.receivedBytes > 0) {
    return '已接收 ${_formatBytes(task.receivedBytes)}';
  }
  return waitSeconds > 0 ? '连接资源中，已等待 ${waitSeconds}s' : '连接资源中';
}

String _downloadAmountLabel(DownloadTask task, {required String fallback}) {
  final totalBytes = task.totalBytes;
  if (totalBytes != null && totalBytes > 0) {
    return '${_formatBytes(task.receivedBytes)} / ${_formatBytes(totalBytes)}';
  }
  if (task.receivedBytes > 0) {
    return '已接收 ${_formatBytes(task.receivedBytes)}';
  }
  return fallback;
}

String _normalizeStatusDetail(String detail) {
  return detail
      .replaceAll('YouTube：', '')
      .replaceAll('直连：', '')
      .replaceAll('…', '')
      .replaceAll('（首次可能较慢）', '')
      .trim();
}

String _compactSavedLocation(String filePath) {
  final normalized = filePath.replaceAll('\\', '/');
  final segments = normalized
      .split('/')
      .where((item) => item.isNotEmpty)
      .toList();
  if (segments.isEmpty) {
    return filePath;
  }
  if (segments.length == 1) {
    return segments.single;
  }
  return '${segments[segments.length - 2]}/${segments.last}';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }

  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }

  final mb = kb / 1024;
  if (mb < 1024) {
    return '${mb.toStringAsFixed(1)} MB';
  }

  final gb = mb / 1024;
  return '${gb.toStringAsFixed(1)} GB';
}

double? _progressIndicatorValue(DownloadTask task) {
  switch (task.status) {
    case DownloadStatus.pending:
      return 0;
    case DownloadStatus.downloading:
      final total = task.totalBytes;
      if (total != null && total > 0) {
        return task.progress.clamp(0.0, 1.0);
      }
      return null;
    case DownloadStatus.completed:
      return 1;
    case DownloadStatus.failed:
    case DownloadStatus.canceled:
      return task.progress.clamp(0.0, 1.0);
  }
}

String _formatDownloadElapsed(DateTime? startedAt) {
  final seconds = _downloadElapsedSeconds(startedAt);
  if (seconds < 0) {
    return '';
  }
  if (seconds < 60) {
    return '已进行 ${seconds}s';
  }
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '已进行 ${minutes}m ${rest}s';
}

int _downloadElapsedSeconds(DateTime? startedAt) {
  if (startedAt == null) {
    return -1;
  }
  return DateTime.now().difference(startedAt).inSeconds;
}

class _DownloadStatusIcon extends StatelessWidget {
  const _DownloadStatusIcon({required this.status});

  final DownloadStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _backgroundColor(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(_icon, color: _foregroundColor(context)),
    );
  }

  Color _backgroundColor(BuildContext context) {
    return switch (status) {
      DownloadStatus.completed => Colors.green.shade100,
      DownloadStatus.failed => Theme.of(context).colorScheme.errorContainer,
      DownloadStatus.canceled => Theme.of(context).colorScheme.surfaceContainer,
      DownloadStatus.pending || DownloadStatus.downloading => Theme.of(
        context,
      ).colorScheme.secondaryContainer,
    };
  }

  Color _foregroundColor(BuildContext context) {
    return switch (status) {
      DownloadStatus.completed => Colors.green.shade800,
      DownloadStatus.failed => Theme.of(context).colorScheme.onErrorContainer,
      DownloadStatus.canceled => Theme.of(context).colorScheme.onSurfaceVariant,
      DownloadStatus.pending || DownloadStatus.downloading => Theme.of(
        context,
      ).colorScheme.onSecondaryContainer,
    };
  }

  IconData get _icon {
    return switch (status) {
      DownloadStatus.pending => Icons.schedule,
      DownloadStatus.downloading => Icons.downloading,
      DownloadStatus.completed => Icons.check,
      DownloadStatus.failed => Icons.error_outline,
      DownloadStatus.canceled => Icons.block,
    };
  }
}

class _TaskActionButton extends StatelessWidget {
  const _TaskActionButton({
    required this.onPressed,
    required this.tooltip,
    required this.icon,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label $count',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

BoxDecoration _panelDecoration(BuildContext context) {
  return BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

Color _statusBadgeBackgroundColor(BuildContext context, DownloadStatus status) {
  final colorScheme = Theme.of(context).colorScheme;
  return switch (status) {
    DownloadStatus.pending => colorScheme.secondaryContainer,
    DownloadStatus.downloading => colorScheme.primaryContainer,
    DownloadStatus.completed => Colors.green.shade100,
    DownloadStatus.failed => colorScheme.errorContainer,
    DownloadStatus.canceled => colorScheme.surfaceContainerHighest,
  };
}

Color _statusBadgeForegroundColor(BuildContext context, DownloadStatus status) {
  final colorScheme = Theme.of(context).colorScheme;
  return switch (status) {
    DownloadStatus.pending => colorScheme.onSecondaryContainer,
    DownloadStatus.downloading => colorScheme.onPrimaryContainer,
    DownloadStatus.completed => Colors.green.shade900,
    DownloadStatus.failed => colorScheme.onErrorContainer,
    DownloadStatus.canceled => colorScheme.onSurfaceVariant,
  };
}
