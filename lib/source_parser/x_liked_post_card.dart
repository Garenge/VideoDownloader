import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'x_likes_models.dart';

class XLikedPostCard extends StatelessWidget {
  const XLikedPostCard({super.key, required this.post});

  final XLikedPost post;

  Future<void> _openPost() async {
    final url = post.url;
    if (url == null || !await launchUrl(Uri.parse(url))) return;
  }

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: post.url == null ? null : _openPost,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(builder: _buildContent),
      ),
    ),
  );

  Widget _buildContent(BuildContext context, BoxConstraints constraints) {
    final compact = constraints.maxWidth < 480;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (post.hasMedia || post.mediaUrl != null) ...[
          _thumbnail(context, constraints.maxWidth < 340 ? 80 : 96),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context),
              if (post.text.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  post.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.35),
                ),
              ],
              const SizedBox(height: 6),
              _footer(context, compact),
            ],
          ),
        ),
      ],
    );
  }

  Widget _thumbnail(BuildContext context, double size) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox.square(
      dimension: size,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: post.mediaUrl == null
            ? _mediaPlaceholder(context)
            : Image.network(
                post.mediaUrl!,
                fit: BoxFit.cover,
                cacheWidth: 288,
                errorBuilder: (_, _, _) => _mediaPlaceholder(context),
              ),
      ),
    ),
  );

  Widget _mediaPlaceholder(BuildContext context) => Icon(
    Icons.perm_media_outlined,
    size: 28,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  Widget _header(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          post.author,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      if (post.createdAt != null) ...[
        const SizedBox(width: 8),
        Text(
          _formatDate(post.createdAt!),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ],
  );

  Widget _footer(BuildContext context, bool compact) => Row(
    children: [
      Expanded(
        child: Text(
          _metrics.join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      if (post.url != null) ...[
        const SizedBox(width: 4),
        IconButton(
          tooltip: '打开原帖',
          onPressed: _openPost,
          icon: const Icon(Icons.open_in_new, size: 16),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: EdgeInsets.zero,
        ),
        if (post.hasMedia) _downloadButton(context, compact),
      ],
    ],
  );

  Widget _downloadButton(BuildContext context, bool compact) {
    void download() => Navigator.of(context).pop(post.url);
    if (compact) {
      return IconButton.filledTonal(
        tooltip: '解析下载',
        onPressed: download,
        icon: const Icon(Icons.download, size: 18),
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: FilledButton.tonalIcon(
        onPressed: download,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
          textStyle: Theme.of(context).textTheme.labelSmall,
        ),
        icon: const Icon(Icons.download, size: 16),
        label: const Text('解析下载'),
      ),
    );
  }

  List<String> get _metrics => [
    if (post.replies != null) '回复 ${post.replies}',
    if (post.reposts != null) '转发 ${post.reposts}',
    if (post.likes != null) '喜欢 ${post.likes}',
    if (post.views != null) '浏览 ${post.views}',
  ];

  String _formatDate(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;
    return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
