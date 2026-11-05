import 'dart:io';
import 'package:flutter/material.dart';
import 'downloaded_file_store.dart';

class DownloadedFileTile extends StatelessWidget {
  const DownloadedFileTile({
    super.key,
    required this.file,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
  });
  final DownloadedFile file;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      key: ValueKey(file.path),
      leading: _thumbnail(),
      title: Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_size()} · ${file.extension.toUpperCase()}\n${_date()}',
      ),
      isThreeLine: true,
      onTap: onOpen,
      trailing: PopupMenuButton<String>(
        tooltip: '文件操作',
        onSelected: (value) => value == 'share' ? onShare() : onDelete(),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'share',
            child: Text(Platform.isIOS ? '分享或导出' : '用系统应用打开'),
          ),
          const PopupMenuItem(value: 'delete', child: Text('删除文件')),
        ],
      ),
    ),
  );

  Widget _thumbnail() {
    final icon = Icon(
      file.isVideo
          ? Icons.play_circle_outline
          : Icons.insert_drive_file_outlined,
      size: 36,
    );
    if (!file.isImage) return SizedBox(width: 48, height: 48, child: icon);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(file.path),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        cacheWidth: 144,
        errorBuilder: (_, error, stack) => icon,
      ),
    );
  }

  String _size() {
    if (file.size < 1024) return '${file.size} B';
    if (file.size < 1024 * 1024) {
      return '${(file.size / 1024).toStringAsFixed(1)} KB';
    }
    return '${(file.size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _date() {
    final time = file.modified.toLocal();
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
