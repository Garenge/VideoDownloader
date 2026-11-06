import 'package:flutter/material.dart';
import 'download_queue_controller.dart';
import 'downloaded_file_actions.dart';
import 'downloaded_file_store.dart';
import 'downloaded_file_tile.dart';
import 'player/local_video_page.dart';

class DownloadedFilesPage extends StatefulWidget {
  const DownloadedFilesPage({super.key, required this.queue, this.store});
  final DownloadQueueController queue;
  final DownloadedFileStore? store;
  @override
  State<DownloadedFilesPage> createState() => _DownloadedFilesPageState();
}

class _DownloadedFilesPageState extends State<DownloadedFilesPage>
    with WidgetsBindingObserver {
  late final DownloadedFileStore _store;
  List<DownloadedFile> _files = [];
  String _query = '';
  String? _error;
  bool _loading = true;
  bool _newestFirst = true;
  int _generation = 0;
  String _snapshot = '';

  @override
  void initState() {
    super.initState();
    _store =
        widget.store ??
        DownloadedFileStore(
          directories: widget.queue.fileDirectories,
          activePaths: () => widget.queue.activeFilePaths,
        );
    WidgetsBinding.instance.addObserver(this);
    widget.queue.addListener(_queueChanged);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.queue.removeListener(_queueChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _queueChanged() {
    final snapshot =
        '${widget.queue.selectedDirectoryPath}|'
        '${widget.queue.history.map((record) => record.filePath).join('|')}|'
        '${widget.queue.activeFilePaths.join('|')}';
    if (snapshot == _snapshot) return;
    _snapshot = snapshot;
    _refresh();
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    try {
      final files = await _store.scan();
      if (!mounted || generation != _generation) return;
      setState(() {
        _files = files;
        _error = null;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = '读取文件失败：$error';
        _loading = false;
      });
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (error) {
      debugPrint('downloaded_files_page.dart#_perform: 文件操作失败 error=$error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('文件操作失败：$error')));
      }
    }
  }

  Future<void> _delete(DownloadedFile file) async {
    if (!await DownloadedFileActions.confirmDelete(context, file) || !mounted) {
      return;
    }
    await _perform(() async {
      await _store.delete(file);
      await widget.queue.removeFileRecords(file.path);
    });
    await _refresh();
  }

  Future<void> _open(DownloadedFile file) async {
    if (file.isVideo) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => LocalVideoPage(file: file)),
      );
    } else {
      await DownloadedFileActions.open(file);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('文件 · ${_files.length}'),
      actions: [
        IconButton(
          tooltip: _newestFirst ? '改为最早优先' : '改为最新优先',
          onPressed: () => setState(() => _newestFirst = !_newestFirst),
          icon: const Icon(Icons.sort),
        ),
        IconButton(
          tooltip: '刷新文件',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索已下载文件',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _query = value.toLowerCase()),
          ),
        ),
        Expanded(child: _body()),
      ],
    ),
  );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final filtered = _files
        .where((file) => file.name.toLowerCase().contains(_query))
        .toList();
    final files = _newestFirst ? filtered : filtered.reversed.toList();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (_error != null)
            ListTile(
              title: Text(_error!),
              trailing: TextButton(
                onPressed: _refresh,
                child: const Text('重试'),
              ),
            ),
          if (files.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _query.isEmpty ? '还没有下载文件，下载完成后可以在这里播放、预览和分享。' : '没有找到匹配的文件',
                textAlign: TextAlign.center,
              ),
            ),
          for (final file in files)
            DownloadedFileTile(
              file: file,
              onOpen: () => _perform(() => _open(file)),
              onShare: () => _perform(() => DownloadedFileActions.share(file)),
              onDelete: () => _delete(file),
            ),
        ],
      ),
    );
  }
}
