import 'package:flutter/material.dart';

import 'x_likes_models.dart';
import 'x_liked_post_card.dart';

class XLikesList extends StatefulWidget {
  const XLikesList({
    super.key,
    required this.posts,
    required this.hasMore,
    required this.loading,
    required this.onLoadMore,
    this.error,
  });

  final List<XLikedPost> posts;
  final bool hasMore;
  final bool loading;
  final VoidCallback onLoadMore;
  final String? error;

  @override
  State<XLikesList> createState() => XLikesListState();
}

class XLikesListState extends State<XLikesList> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final posts = widget.posts.where((post) {
      if (_query.isEmpty) return true;
      return post.text.toLowerCase().contains(_query) ||
          post.author.toLowerCase().contains(_query);
    }).toList();
    if (widget.posts.isEmpty) {
      return _footer();
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Text(
                '已加载 ${widget.posts.length} 条',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 20),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    hintText: '搜索作者或正文',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: posts.isEmpty
              ? Column(children: [const Text('没有匹配的点赞内容'), _footer()])
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: posts.length + 1,
                  itemBuilder: (context, index) => index == posts.length
                      ? _footer()
                      : XLikedPostCard(post: posts[index]),
                ),
        ),
      ],
    );
  }

  Widget _footer() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.error != null)
          Text(widget.error!, textAlign: TextAlign.center),
        if (widget.loading)
          const CircularProgressIndicator()
        else if (widget.hasMore)
          TextButton(
            onPressed: widget.onLoadMore,
            child: Text(widget.error == null ? '加载更多' : '重试加载更多'),
          )
        else
          Text(widget.posts.isEmpty ? '还没有点赞内容' : '已加载全部可用内容'),
      ],
    ),
  );
}
