import 'dart:io';

import 'package:flutter/material.dart';

import 'downloaded_file_store.dart';
import 'downloaded_files_selection.dart';

enum DownloadedFileFilter {
  all('全部'),
  images('图片'),
  videos('视频');

  const DownloadedFileFilter(this.label);
  final String label;

  bool matches(DownloadedFile file) => switch (this) {
    all => true,
    images => file.isImage,
    videos => file.isVideo,
  };
}

class DownloadedFilesFilterBar extends StatelessWidget {
  const DownloadedFilesFilterBar({
    super.key,
    required this.filter,
    required this.onChanged,
  });

  final DownloadedFileFilter filter;
  final ValueChanged<DownloadedFileFilter>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
    child: SegmentedButton<DownloadedFileFilter>(
      segments: [
        for (final value in DownloadedFileFilter.values)
          ButtonSegment(value: value, label: Text(value.label)),
      ],
      selected: {filter},
      onSelectionChanged: onChanged == null
          ? null
          : (values) => onChanged!(values.single),
    ),
  );
}

class DownloadedFilesSelectionBar extends StatelessWidget {
  const DownloadedFilesSelectionBar({
    super.key,
    required this.selection,
    required this.visibleFiles,
    required this.onDelete,
    required this.onShare,
    this.enabled = true,
  });

  final DownloadedFilesSelection selection;
  final List<DownloadedFile> visibleFiles;
  final VoidCallback onDelete;
  final VoidCallback onShare;
  final bool enabled;
  bool get _blocked => selection.busy || !enabled;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text('已选 ${selection.count} 项'),
          TextButton(
            onPressed: _blocked || visibleFiles.isEmpty
                ? null
                : () => selection.selectAll(visibleFiles),
            child: const Text('全选'),
          ),
          TextButton(
            onPressed: _blocked ? null : selection.clear,
            child: const Text('取消选择'),
          ),
          if (Platform.isIOS)
            TextButton.icon(
              onPressed: _enabled ? onShare : null,
              icon: const Icon(Icons.ios_share),
              label: const Text('分享/导出'),
            ),
          TextButton.icon(
            onPressed: _enabled ? onDelete : null,
            icon: const Icon(Icons.delete_outline),
            label: const Text('批量删除'),
          ),
          if (selection.busy) const Text('处理中…'),
        ],
      ),
    ),
  );

  bool get _enabled => !_blocked && selection.count > 0;
}
