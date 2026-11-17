import 'package:flutter/material.dart';

import 'downloaded_file_store.dart';

enum DownloadedFilesSort {
  newest('时间 · 最新优先'),
  oldest('时间 · 最早优先'),
  largest('大小 · 从大到小'),
  smallest('大小 · 从小到大'),
  nameAscending('名字 · 升序'),
  nameDescending('名字 · 降序');

  const DownloadedFilesSort(this.label);
  final String label;

  int compare(DownloadedFile a, DownloadedFile b) {
    final result = switch (this) {
      newest => b.modified.compareTo(a.modified),
      oldest => a.modified.compareTo(b.modified),
      largest => b.size.compareTo(a.size),
      smallest => a.size.compareTo(b.size),
      nameAscending => compareFileNames(a.name, b.name),
      nameDescending => compareFileNames(b.name, a.name),
    };
    return result == 0 ? a.path.compareTo(b.path) : result;
  }
}

int compareFileNames(String a, String b) {
  final parts = RegExp(r'\d+|\D+');
  final left = parts.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final right = parts.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var index = 0; index < left.length && index < right.length; index++) {
    final result = _comparePart(left[index], right[index]);
    if (result != 0) return result;
  }
  return left.length.compareTo(right.length);
}

int _comparePart(String a, String b) {
  final left = BigInt.tryParse(a);
  final right = BigInt.tryParse(b);
  return left != null && right != null ? left.compareTo(right) : a.compareTo(b);
}

class DownloadedFilesSortButton extends StatelessWidget {
  const DownloadedFilesSortButton({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final DownloadedFilesSort value;
  final ValueChanged<DownloadedFilesSort>? onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<DownloadedFilesSort>(
    tooltip: '排序：${value.label}',
    enabled: onChanged != null,
    initialValue: value,
    onSelected: onChanged,
    icon: const Icon(Icons.sort),
    itemBuilder: (_) => [
      for (final option in DownloadedFilesSort.values)
        CheckedPopupMenuItem(
          value: option,
          checked: option == value,
          child: Text(option.label),
        ),
    ],
  );
}
