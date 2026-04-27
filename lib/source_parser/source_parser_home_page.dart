import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import 'download_queue_controller.dart';
import 'download_queue_panel.dart';
import 'source_parser_service.dart';
import 'source_resource.dart';

class SourceParserHomePage extends StatefulWidget {
  const SourceParserHomePage({super.key, this.parserService});

  final SourceParserService? parserService;

  @override
  State<SourceParserHomePage> createState() => _SourceParserHomePageState();
}

class _SourceParserHomePageState extends State<SourceParserHomePage> {
  final _urlController = TextEditingController();
  late final SourceParserService _parserService;
  late final DownloadQueueController _downloadQueueController;

  SourceParseResult? _result;
  SourceResourceType? _selectedType;
  String? _errorText;
  bool _isParsing = false;

  @override
  void initState() {
    super.initState();
    _parserService = widget.parserService ?? SourceParserService();
    _downloadQueueController = DownloadQueueController();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _downloadQueueController.dispose();
    super.dispose();
  }

  Future<void> _handleParse() async {
    final error = _parserService.validate(_urlController.text);
    if (error != null) {
      setState(() {
        _errorText = error;
      });
      return;
    }

    setState(() {
      _errorText = null;
      _selectedType = null;
      _isParsing = true;
    });

    try {
      final result = await _parserService.parse(_urlController.text);
      if (!mounted) {
        return;
      }

      setState(() {
        _result = result;
      });
    } on SourceParserException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorText = error.message;
        _result = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isParsing = false;
        });
      }
    }
  }

  void _handleDownload(SourceResource resource) {
    final task = _downloadQueueController.enqueue(resource);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已加入下载队列：${task.fileName}')));
  }

  Future<void> _handleSelectDownloadDirectory() async {
    final directoryPath = await getDirectoryPath(confirmButtonText: '选择保存目录');
    if (directoryPath == null || directoryPath.trim().isEmpty) {
      return;
    }

    _downloadQueueController.setDownloadDirectory(directoryPath);
  }

  void _handleResetDownloadDirectory() {
    _downloadQueueController.resetDownloadDirectory();
  }

  Future<void> _handleOpenDownloadedFolder(DownloadTask task) async {
    try {
      await _downloadQueueController.openDownloadedFolder(task);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('打开文件夹失败：$error')));
    }
  }

  void _selectType(SourceResourceType? type) {
    setState(() {
      _selectedType = type;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(context),
                      const SizedBox(height: 22),
                      _buildParserPanel(context),
                      const SizedBox(height: 20),
                      _buildDownloadSettingsSection(context),
                      const SizedBox(height: 20),
                      _buildResultSection(context),
                      const SizedBox(height: 20),
                      _buildDownloadQueueSection(context),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.travel_explore, color: Colors.white),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '网页资源解析',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '粘贴链接，识别视频、图片和其他可下载资源',
                style: textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildParserPanel(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: '目标 URL',
                hintText: 'https://www.youtube.com/watch?v=...',
                errorText: _errorText,
                prefixIcon: const Icon(Icons.link),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              onSubmitted: (_) {
                if (!_isParsing) {
                  _handleParse();
                }
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _buildPlatformHints(context)),
                const SizedBox(width: 14),
                FilledButton.icon(
                  onPressed: _isParsing ? null : _handleParse,
                  icon: _isParsing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(_isParsing ? '解析中' : '解析'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformHints(BuildContext context) {
    final platforms = SourcePlatform.values;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final platform in platforms)
          Chip(
            avatar: Icon(_platformIcon(platform), size: 18),
            label: Text(platform.displayName),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _buildResultSection(BuildContext context) {
    if (_isParsing) {
      return _buildLoadingState(context);
    }

    final result = _result;
    if (result == null) {
      return _buildEmptyState(context);
    }

    final visibleResources = _visibleResources(result);
    final message = result.message;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSummaryBar(context, result),
        const SizedBox(height: 14),
        _buildTypeFilters(result),
        const SizedBox(height: 14),
        if (visibleResources.isEmpty && message != null)
          _buildNoResources(context, message)
        else if (visibleResources.isEmpty)
          _buildNoResources(context, '当前分类下没有资源')
        else
          _buildResourceGroups(visibleResources),
      ],
    );
  }

  Widget _buildDownloadSettingsSection(BuildContext context) {
    return AnimatedBuilder(
      animation: _downloadQueueController,
      builder: (context, _) {
        return DownloadSettingsPanel(
          selectedDirectoryPath: _downloadQueueController.selectedDirectoryPath,
          onSelectDirectory: _handleSelectDownloadDirectory,
          onResetDirectory: _handleResetDownloadDirectory,
        );
      },
    );
  }

  Widget _buildDownloadQueueSection(BuildContext context) {
    return AnimatedBuilder(
      animation: _downloadQueueController,
      builder: (context, _) {
        if (!_downloadQueueController.hasTasks) {
          return const SizedBox.shrink();
        }

        return DownloadQueuePanel(
          tasks: _downloadQueueController.tasks,
          onCancel: _downloadQueueController.cancel,
          onOpenFolder: _handleOpenDownloadedFolder,
        );
      },
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(context),
      child: const Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('正在读取网页源码并提取资源'),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(
              Icons.manage_search,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              '等待解析',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '支持抖音、X、YouTube、Bilibili，其他来源会归入其他分类。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBar(BuildContext context, SourceParseResult result) {
    return DecoratedBox(
      decoration: _panelDecoration(context),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(_platformIcon(result.platform)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.platform.displayName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    result.originalUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            _CountPill(label: '资源', count: result.resources.length),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeFilters(SourceParseResult result) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: Text('全部 ${result.resources.length}'),
          selected: _selectedType == null,
          onSelected: (_) => _selectType(null),
        ),
        for (final type in SourceResourceType.values)
          ChoiceChip(
            label: Text(
              '${type.displayName} ${result.resourcesOf(type).length}',
            ),
            selected: _selectedType == type,
            onSelected: (_) => _selectType(type),
          ),
      ],
    );
  }

  Widget _buildNoResources(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildResourceGroups(List<SourceResource> resources) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in SourceResourceType.values)
          if (resources.any((resource) => resource.type == type)) ...[
            _ResourceGroup(
              title: type.displayName,
              icon: _typeIcon(type),
              resources: resources
                  .where((resource) => resource.type == type)
                  .toList(),
              onDownload: _handleDownload,
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  List<SourceResource> _visibleResources(SourceParseResult result) {
    final selectedType = _selectedType;
    if (selectedType == null) {
      return result.resources;
    }

    return result.resourcesOf(selectedType);
  }

  BoxDecoration _panelDecoration(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    );
  }

  IconData _platformIcon(SourcePlatform platform) {
    return switch (platform) {
      SourcePlatform.douyin => Icons.music_video,
      SourcePlatform.x => Icons.alternate_email,
      SourcePlatform.youtube => Icons.play_circle,
      SourcePlatform.bilibili => Icons.ondemand_video,
      SourcePlatform.other => Icons.public,
    };
  }

  IconData _typeIcon(SourceResourceType type) {
    return switch (type) {
      SourceResourceType.video => Icons.movie,
      SourceResourceType.image => Icons.image,
      SourceResourceType.other => Icons.description,
    };
  }
}

class _ResourceGroup extends StatelessWidget {
  const _ResourceGroup({
    required this.title,
    required this.icon,
    required this.resources,
    required this.onDownload,
  });

  final String title;
  final IconData icon;
  final List<SourceResource> resources;
  final ValueChanged<SourceResource> onDownload;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final resource in resources) ...[
              _ResourceTile(
                resource: resource,
                onDownload: () => onDownload(resource),
              ),
              if (resource != resources.last) const Divider(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResourceTile extends StatelessWidget {
  const _ResourceTile({required this.resource, required this.onDownload});

  final SourceResource resource;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TypeIcon(type: resource.type),
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
              const SizedBox(height: 2),
              Text(
                '${resource.host} · ${resource.sizeHint}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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

class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.type});

  final SourceResourceType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _icon,
        color: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    );
  }

  IconData get _icon {
    return switch (type) {
      SourceResourceType.video => Icons.movie,
      SourceResourceType.image => Icons.image,
      SourceResourceType.other => Icons.description,
    };
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
