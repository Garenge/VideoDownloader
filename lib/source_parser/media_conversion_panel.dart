import 'package:flutter/material.dart';

import 'media_conversion_controller.dart';

class MediaConversionPanel extends StatelessWidget {
  const MediaConversionPanel({
    super.key,
    required this.tasks,
    required this.onCancel,
    required this.onRetry,
    required this.onOpenFolder,
  });

  final List<MediaConversionTask> tasks;
  final ValueChanged<MediaConversionTask> onCancel;
  final ValueChanged<MediaConversionTask> onRetry;
  final ValueChanged<MediaConversionTask> onOpenFolder;

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
                const Icon(Icons.movie_creation_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  '转格式任务',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                _CountPill(label: '任务', count: tasks.length),
              ],
            ),
            const SizedBox(height: 10),
            if (tasks.isEmpty)
              Text(
                '从下载历史里的 m3u8 条目发起转 MP4，任务会在这里排队执行。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final task in tasks) ...[
                _MediaConversionTaskTile(
                  task: task,
                  onCancel: () => onCancel(task),
                  onRetry: () => onRetry(task),
                  onOpenFolder: () => onOpenFolder(task),
                ),
                if (task != tasks.last) const Divider(height: 14),
              ],
          ],
        ),
      ),
    );
  }
}

class _MediaConversionTaskTile extends StatelessWidget {
  const _MediaConversionTaskTile({
    required this.task,
    required this.onCancel,
    required this.onRetry,
    required this.onOpenFolder,
  });

  final MediaConversionTask task;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final canCancel =
        task.status == MediaConversionStatus.pending ||
        task.status == MediaConversionStatus.converting;
    final canRetry = task.status == MediaConversionStatus.failed;
    final canOpenFolder =
        task.status == MediaConversionStatus.completed &&
        task.outputFilePath != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MediaConversionStatusIcon(status: task.status),
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
                task.outputFileName,
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
        const SizedBox(height: 4),
        Text(
          '来源：${task.inputRecord.fileName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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

    final outputFilePath = task.outputFilePath;
    if (outputFilePath != null &&
        task.status == MediaConversionStatus.completed) {
      return outputFilePath;
    }

    final elapsed = _formatTaskElapsed(task.activeStartedAt);
    final detail = task.statusDetail;
    final progressText = task.progressLabel;

    if (elapsed.isEmpty) {
      return detail != null && detail.isNotEmpty
          ? '$detail · $progressText'
          : progressText;
    }

    if (detail != null && detail.isNotEmpty) {
      return '$elapsed · $detail · $progressText';
    }

    return '$elapsed · $progressText';
  }
}

double? _progressIndicatorValue(MediaConversionTask task) {
  switch (task.status) {
    case MediaConversionStatus.pending:
      return 0;
    case MediaConversionStatus.converting:
      return task.progress > 0 ? task.progress.clamp(0.0, 1.0) : null;
    case MediaConversionStatus.completed:
      return 1;
    case MediaConversionStatus.failed:
    case MediaConversionStatus.canceled:
      return task.progress > 0 ? task.progress.clamp(0.0, 1.0) : 0;
  }
}

String _formatTaskElapsed(DateTime? startedAt) {
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

class _MediaConversionStatusIcon extends StatelessWidget {
  const _MediaConversionStatusIcon({required this.status});

  final MediaConversionStatus status;

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
    final colorScheme = Theme.of(context).colorScheme;
    return switch (status) {
      MediaConversionStatus.pending => colorScheme.surfaceContainerHighest,
      MediaConversionStatus.converting => colorScheme.primaryContainer,
      MediaConversionStatus.completed => colorScheme.secondaryContainer,
      MediaConversionStatus.failed => colorScheme.errorContainer,
      MediaConversionStatus.canceled => colorScheme.tertiaryContainer,
    };
  }

  Color _foregroundColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return switch (status) {
      MediaConversionStatus.pending => colorScheme.onSurfaceVariant,
      MediaConversionStatus.converting => colorScheme.onPrimaryContainer,
      MediaConversionStatus.completed => colorScheme.onSecondaryContainer,
      MediaConversionStatus.failed => colorScheme.onErrorContainer,
      MediaConversionStatus.canceled => colorScheme.onTertiaryContainer,
    };
  }

  IconData get _icon {
    return switch (status) {
      MediaConversionStatus.pending => Icons.schedule,
      MediaConversionStatus.converting => Icons.sync,
      MediaConversionStatus.completed => Icons.movie_creation,
      MediaConversionStatus.failed => Icons.error_outline,
      MediaConversionStatus.canceled => Icons.block,
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
