import 'package:flutter/material.dart';

import 'x_likes_service.dart';
import 'x_likes_list.dart';

class XLikesPage extends StatefulWidget {
  const XLikesPage({super.key});
  @override
  State<XLikesPage> createState() => _XLikesPageState();
}

class _XLikesPageState extends State<XLikesPage> {
  final _service = XLikesService();
  final _posts = <String, XLikedPost>{};
  String? _cursor;
  String? _error;
  String _rawJson = '';
  bool _loading = false;
  bool _loaded = false;
  bool _retryRefresh = false;

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _service.fetchLikes(
        cursor: refresh ? null : _cursor,
      );
      if (!mounted) return;
      setState(() {
        if (refresh) _posts.clear();
        for (final post in response.posts) {
          _posts[post.id] = post;
        }
        _cursor = response.nextCursor;
        _rawJson = response.rawJson;
        _loaded = true;
        _retryRefresh = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _retryRefresh =
            refresh || (error is XLikesException && error.requiresRefresh);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('X 点赞列表'),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _loading ? null : () => _load(refresh: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: !_loaded ? _initialView() : _results(),
  );

  Widget _initialView() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error ?? '没有返回数据', textAlign: TextAlign.center),
          TextButton(
            onPressed: () => _load(refresh: true),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _results() => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: '点赞内容'),
            Tab(text: '最近一页 JSON'),
          ],
        ),
        if (_error != null && _cursor == null)
          Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        Expanded(
          child: TabBarView(
            children: [
              XLikesList(
                posts: _posts.values.toList(),
                hasMore: _cursor != null,
                loading: _loading,
                error: _cursor == null ? null : _error,
                onLoadMore: () => _load(refresh: _retryRefresh),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(_rawJson),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
