import 'package:flutter/material.dart';

import 'download_queue_controller.dart';

class DownloadSettingsPanel extends StatelessWidget {
  const DownloadSettingsPanel({
    super.key,
    required this.selectedDirectoryPath,
    required this.onSelectDirectory,
    required this.onResetDirectory,
  });

  final String? selectedDirectoryPath;
  final VoidCallback onSelectDirectory;
  final VoidCallback onResetDirectory;

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
            IconButton(
              onPressed: onSelectDirectory,
              tooltip: '选择保存目录',
              icon: const Icon(Icons.drive_folder_upload),
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
      ],
    );
  }
}

class DownloadQueuePanel extends StatelessWidget {
  const DownloadQueuePanel({
    super.key,
    required this.tasks,
    required this.onCancel,
    required this.onOpenFolder,
  });

  final List<DownloadTask> tasks;
  final ValueChanged<DownloadTask> onCancel;
  final ValueChanged<DownloadTask> onOpenFolder;

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

class _DownloadTaskTile extends StatelessWidget {
  const _DownloadTaskTile({
    required this.task,
    required this.onCancel,
    required this.onOpenFolder,
  });

  final DownloadTask task;
  final VoidCallback onCancel;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final canCancel =
        task.status == DownloadStatus.pending ||
        task.status == DownloadStatus.downloading;
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
          value: task.status == DownloadStatus.downloading
              ? task.progress == 0
                    ? null
                    : task.progress
              : task.progress,
          minHeight: 6,
          borderRadius: BorderRadius.circular(6),
        ),
        const SizedBox(height: 6),
        Text(
          _taskDetail,
          maxLines: 2,
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

    return task.progressLabel;
  }
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
