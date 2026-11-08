import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'x_likes_service.dart';

class XLikesPage extends StatefulWidget {
  const XLikesPage({super.key});

  @override
  State<XLikesPage> createState() => _XLikesPageState();
}

class _XLikesPageState extends State<XLikesPage> {
  final _service = XLikesService();
  Future<XLikesResponse>? _request;

  @override
  void initState() {
    super.initState();
    _request = _service.fetchLikes();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  void _load() {
    final request = _service.fetchLikes();
    if (!mounted) return;
    setState(() {
      _request = request;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('X 点赞列表'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<XLikesResponse>(
        future: _request,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error!, onRetry: _load);
          }
          final response = snapshot.data;
          if (response == null) {
            return const Center(child: Text('没有返回数据'));
          }
          return _LikesResultView(response: response);
        },
      ),
    );
  }
}

class _LikesResultView extends StatelessWidget {
  const _LikesResultView({required this.response});

  final XLikesResponse response;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              tabs: [
                Tab(text: '点赞内容'),
                Tab(text: '原始 JSON'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _PostsList(posts: response.posts),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(response.rawJson),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PostsList extends StatefulWidget {
  const _PostsList({required this.posts});

  final List<XLikedPost> posts;

  @override
  State<_PostsList> createState() => _PostsListState();
}

class _PostsListState extends State<_PostsList> {
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
      return const Center(child: Text('接口返回成功，但没有解析到点赞内容'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              Text(
                '已加载 ${widget.posts.length} 条',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
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
              ? const Center(child: Text('没有匹配的点赞内容'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: posts.length,
                  itemBuilder: (context, index) =>
                      _PostCard(post: posts[index]),
                ),
        ),
      ],
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post});

  final XLikedPost post;

  Future<void> _openPost() async {
    final url = post.url;
    if (url == null || !await launchUrl(Uri.parse(url))) return;
  }

  @override
  Widget build(BuildContext context) {
    final metrics = <String>[
      if (post.replies != null) '回复 ${post.replies}',
      if (post.reposts != null) '转发 ${post.reposts}',
      if (post.likes != null) '喜欢 ${post.likes}',
      if (post.views != null) '浏览 ${post.views}',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: post.url == null ? null : _openPost,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    child: Text(
                      post.author.replaceFirst('@', '').characters.first,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      post.author,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (post.createdAt != null)
                    Text(
                      _formatDate(post.createdAt!),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  if (post.url != null)
                    IconButton(
                      tooltip: '打开原帖',
                      onPressed: _openPost,
                      icon: const Icon(Icons.open_in_new),
                    ),
                ],
              ),
              if (post.text.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(post.text, style: Theme.of(context).textTheme.bodyLarge),
              ],
              if (post.mediaUrl != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    post.mediaUrl!,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
              if (metrics.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  metrics.join('  ·  '),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;
    return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
