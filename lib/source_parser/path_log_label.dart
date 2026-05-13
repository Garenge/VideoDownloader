String pathLogLabel(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    return '-';
  }

  final normalized = trimmed.replaceAll(r'\', '/');
  final parts = normalized
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  return parts.isEmpty ? trimmed : parts.last;
}
