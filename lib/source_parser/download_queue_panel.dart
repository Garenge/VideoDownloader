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
          path ?? '默认保存到应用文档目录',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          downloadSettings.enableYtDlpFallback ? 'YouTube 兜底：开启' : 'YouTube 兜底：关闭',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
    required this.onClear,
  });

  final List<DownloadHistoryRecord> records;
  final ValueChanged<DownloadHistoryRecord> onOpenFolder;
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
  });

  final DownloadHistoryRecord record;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DownloadStatusIcon(status: DownloadStatus.completed),
        const SizedBox(width: 12),
        Expanded(child: _buildRecordContent(context)),
        const SizedBox(width: 8),
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DownloadStatusIcon(status: task.status),
        const SizedBox(width: 12),
        Expanded(child: _buildTaskContent(context)),
        if (canOpenFolder) ...[
          const SizedBox(width: 8),
          IconButton(
            onPressed: onOpenFolder,
            tooltip: '打开所在文件夹',
            icon: const Icon(Icons.folder_open),
          ),
        ],
        if (canRetry) ...[
          const SizedBox(width: 8),
          IconButton(
            onPressed: onRetry,
            tooltip: '重试',
            icon: const Icon(Icons.refresh),
          ),
        ],
        if (canCopyLogs) ...[
          const SizedBox(width: 8),
          IconButton(
            onPressed: onCopyLogs,
            tooltip: '复制日志',
            icon: const Icon(Icons.copy_all),
          ),
        ],
        if (canCancel) ...[
          const SizedBox(width: 8),
          IconButton(
            onPressed: onCancel,
            tooltip: '取消',
            icon: const Icon(Icons.close),
          ),
        ],
      ],
    );
  }

  Widget _buildTaskContent(BuildContext context) {
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
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              task.status.displayName,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        Text(
          _taskDetail,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String get _taskDetail {
    final error = task.errorMessage;
    if (error != null) {
      return error;
    }

    final filePath = task.filePath;
    if (filePath != null && task.status == DownloadStatus.completed) {
      return filePath;
    }

    final elapsed = _formatDownloadElapsed(task.activeStartedAt);
    final detail = task.statusDetail;
    final progressText = task.progressLabel;

    if (elapsed.isEmpty) {
      return detail != null && detail.isNotEmpty ? '$detail · $progressText' : progressText;
    }

    if (detail != null && detail.isNotEmpty) {
      return '$elapsed · $detail · $progressText';
    }

    return '$elapsed · $progressText';
  }
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
  if (startedAt == null) {
    return '';
  }
  final seconds = DateTime.now().difference(startedAt).inSeconds;
  if (seconds < 60) {
    return '已进行 ${seconds}s';
  }
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '已进行 ${minutes}m ${rest}s';
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
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
  );
}
