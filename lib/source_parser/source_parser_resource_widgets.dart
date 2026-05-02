part of 'source_parser_home_page.dart';

class _ResourceTile extends StatelessWidget {
  const _ResourceTile({
    required this.resource,
    required this.onDownload,
    required this.imageRequestReferrer,
  });

  final SourceResource resource;
  final VoidCallback onDownload;
  final String? imageRequestReferrer;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ResourcePreview(
          resource: resource,
          imageRequestReferrer: imageRequestReferrer,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                resource.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '${resource.host} · ${resource.fileExtension.toUpperCase()} · ${resource.sizeHint}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.link,
                    size: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      resource.url,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          onPressed: onDownload,
          tooltip: '下载',
          icon: const Icon(Icons.download),
        ),
      ],
    );
  }
}

class _ResourcePreview extends StatelessWidget {
  const _ResourcePreview({
    required this.resource,
    required this.imageRequestReferrer,
  });

  final SourceResource resource;
  final String? imageRequestReferrer;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 96,
        height: 68,
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (resource.type == SourceResourceType.image) {
      final referrer = imageRequestReferrer?.trim();
      final headers = <String, String>{
        'User-Agent': 'VideoDownloader/1.0',
        if (referrer != null && referrer.isNotEmpty) 'Referer': referrer,
      };

      return ResourceThumbnailImage(
        key: ValueKey('resource-preview-image-${resource.url}'),
        imageUrl: resource.url,
        headers: headers,
        httpClient: ResourceHttpClientScope.clientOf(context),
        fit: BoxFit.cover,
        placeholderColor: Theme.of(context).colorScheme.secondaryContainer,
        errorWidget: _buildIcon(context),
      );
    }

    return _buildIcon(context);
  }

  Widget _buildIcon(BuildContext context) {
    return Icon(
      _icon,
      color: Theme.of(context).colorScheme.onSecondaryContainer,
    );
  }

  IconData get _icon {
    return switch (resource.type) {
      SourceResourceType.video => Icons.movie,
      SourceResourceType.image => Icons.image,
      SourceResourceType.other => Icons.description,
    };
  }
}

class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('全部')),
          for (final item in values)
            DropdownMenuItem<String>(
              value: item,
              child: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label $count',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
