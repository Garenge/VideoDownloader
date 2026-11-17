import 'package:flutter/material.dart';
import 'download_queue_controller.dart';
import 'downloaded_file_actions.dart';
import 'downloaded_file_store.dart';
import 'downloaded_file_tile.dart';
import 'downloaded_file_batch_actions.dart';
import 'downloaded_files_controls.dart';
import 'downloaded_files_selection.dart';
import 'downloaded_files_sort.dart';
import 'player/local_image_page.dart';
import 'player/local_video_page.dart';

class DownloadedFilesPage extends StatefulWidget {
  const DownloadedFilesPage({
    super.key,
    required this.queue,
    this.store,
    this.embedded = false,
  });
  final bool embedded;
  final DownloadQueueController queue;
  final DownloadedFileStore? store;
  @override
  State<DownloadedFilesPage> createState() => _DownloadedFilesPageState();
}

class _DownloadedFilesPageState extends State<DownloadedFilesPage>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  late final DownloadedFileStore _store;
  List<DownloadedFile> _files = [];
  String _query = '';
  String? _error;
  bool _loading = true;
  DownloadedFilesSort _sort = DownloadedFilesSort.newest;
  bool _refreshing = false;
  int _generation = 0;
  String _snapshot = '';
  final _selection = DownloadedFilesSelection();
  DownloadedFileFilter _filter = DownloadedFileFilter.all;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _selection.addListener(_selectionChanged);
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
    _selection.removeListener(_selectionChanged);
    _selection.dispose();
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

  Future<void> _refresh({bool feedback = false}) async {
    if (_refreshing || (feedback && _selection.busy)) return;
    if (feedback) setState(() => _refreshing = true);
    final generation = ++_generation;
    try {
      final files = await _store.scan();
      if (!mounted || generation != _generation) return;
      setState(() {
        _files = files;
        _error = null;
        _loading = false;
      });
      _selection.retain(files);
      if (feedback) _showMessage('刷新成功，共 ${files.length} 个文件');
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = '读取文件失败：$error';
        _loading = false;
      });
      if (feedback) _showMessage('刷新失败：$error');
    } finally {
      if (feedback && mounted) setState(() => _refreshing = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _changeSort(DownloadedFilesSort value) {
    if (value == _sort) return;
    setState(() => _sort = value);
    _showMessage('已按${value.label}排序');
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
        MaterialPageRoute(
          builder: (_) => LocalVideoPage(
            file: file,
            files: _visibleFiles.where((item) => item.isVideo).toList(),
          ),
        ),
      );
    } else if (file.isImage) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => LocalImagePage(
            file: file,
            files: _visibleFiles.where((item) => item.isImage).toList(),
          ),
        ),
      );
    } else {
      await DownloadedFileActions.open(file);
    }
  }

  void _selectionChanged() {
    if (mounted) setState(() {});
  }

  List<DownloadedFile> get _visibleFiles {
    final files = _files
        .where(
          (file) =>
              _filter.matches(file) && file.name.toLowerCase().contains(_query),
        )
        .toList();
    return files..sort(_sort.compare);
  }

  Future<void> _deleteSelected() => DownloadedFileBatchActions.delete(
    context: context,
    files: _selection.selected(_files),
    selection: _selection,
    store: _store,
    queue: widget.queue,
    refresh: _refresh,
  );

  void _changeFilter(DownloadedFileFilter value) {
    setState(() => _filter = value);
    _selection.clear();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(
          _selection.selecting
              ? '已选 ${_selection.count} 项'
              : '文件 · ${_visibleFiles.length}',
        ),
        actions: [
          TextButton(
            onPressed: _selection.busy || _refreshing
                ? null
                : () {
                    if (_selection.selecting) {
                      _selection.clear(exit: true);
                    } else {
                      _selection.enter();
                    }
                  },
            child: Text(_selection.selecting ? '完成' : '选择'),
          ),
          DownloadedFilesSortButton(
            value: _sort,
            onChanged: _selection.busy || _refreshing ? null : _changeSort,
          ),
          IconButton(
            tooltip: '刷新文件',
            onPressed: _selection.busy || _refreshing
                ? null
                : () => _refresh(feedback: true),
            icon: Icon(_refreshing ? Icons.hourglass_top : Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              enabled: !_selection.busy,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索已下载文件',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() => _query = value.toLowerCase());
                _selection.clear();
              },
            ),
          ),
          DownloadedFilesFilterBar(
            filter: _filter,
            onChanged: _selection.busy ? null : _changeFilter,
          ),
          Expanded(
            child: AbsorbPointer(absorbing: _refreshing, child: _body()),
          ),
        ],
      ),
      bottomNavigationBar: _selection.selecting
          ? DownloadedFilesSelectionBar(
              selection: _selection,
              enabled: !_refreshing,
              visibleFiles: _visibleFiles,
              onDelete: _deleteSelected,
              onShare: () => _perform(
                () => DownloadedFileBatchActions.share(
                  _selection.selected(_files),
                  _selection,
                ),
              ),
            )
          : null,
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final files = _visibleFiles;
    return RefreshIndicator(
      onRefresh: () => _refresh(feedback: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (_error != null)
            ListTile(
              title: Text(_error!),
              trailing: TextButton(
                onPressed: () => _refresh(feedback: true),
                child: const Text('重试'),
              ),
            ),
          if (files.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _files.isEmpty ? '还没有下载文件，下载完成后可以在这里播放、预览和分享。' : '没有找到匹配的文件',
                textAlign: TextAlign.center,
              ),
            ),
          for (final file in files)
            DownloadedFileTile(
              file: file,
              selecting: _selection.selecting,
              selected: _selection.contains(file),
              onToggle: _selection.busy ? null : () => _selection.toggle(file),
              onOpen: () => _perform(() => _open(file)),
              onShare: () => _perform(() => DownloadedFileActions.share(file)),
              onDelete: () => _delete(file),
            ),
        ],
      ),
    );
  }
}
