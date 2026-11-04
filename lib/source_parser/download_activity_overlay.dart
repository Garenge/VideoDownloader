import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 右下角悬浮下载入口与弹出面板（队列 + 历史）。
class DownloadActivityOverlay extends StatelessWidget {
  const DownloadActivityOverlay({
    super.key,
    required this.panelOpen,
    required this.onTogglePanel,
    required this.onClosePanel,
    required this.activeTaskCount,
    required this.queuePanel,
    required this.conversionPanel,
    required this.historyPanel,
  });

  final bool panelOpen;
  final VoidCallback onTogglePanel;
  final VoidCallback onClosePanel;
  final int activeTaskCount;
  final Widget queuePanel;
  final Widget? conversionPanel;
  final Widget historyPanel;

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final maxW = math.min(400.0, MediaQuery.sizeOf(context).width - 32);
    final maxH = math.min(480.0, MediaQuery.sizeOf(context).height * 0.58);
    final badgeVisible = activeTaskCount > 0;

    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        if (panelOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClosePanel,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
            ),
          ),
        Positioned(
          right: 16,
          bottom: 16 + bottomSafe,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomRight,
                child: panelOpen
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _DownloadPanelCard(
                            width: maxW,
                            height: maxH,
                            onClose: onClosePanel,
                            queuePanel: queuePanel,
                            conversionPanel: conversionPanel,
                            historyPanel: historyPanel,
                          ),
                          const SizedBox(height: 12),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              Badge(
                isLabelVisible: badgeVisible,
                label: Text('$activeTaskCount'),
                offset: const Offset(10, -6),
                child: FloatingActionButton(
                  key: const ValueKey('download-activity-fab'),
                  tooltip: '下载队列与历史',
                  onPressed: onTogglePanel,
                  child: const Icon(Icons.download_done),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DownloadPanelCard extends StatelessWidget {
  const _DownloadPanelCard({
    required this.width,
    required this.height,
    required this.onClose,
    required this.queuePanel,
    required this.conversionPanel,
    required this.historyPanel,
  });

  final double width;
  final double height;
  final VoidCallback onClose;
  final Widget queuePanel;
  final Widget? conversionPanel;
  final Widget historyPanel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 10,
      shadowColor: Colors.black45,
      surfaceTintColor: theme.colorScheme.surfaceTint,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: DefaultTabController(
          length: conversionPanel == null ? 2 : 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: theme.colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_special_outlined,
                        size: 22,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '下载',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '收起',
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
              TabBar(
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                tabs: [
                  const Tab(text: '队列'),
                  if (conversionPanel != null) const Tab(text: '转换'),
                  const Tab(text: '历史'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _ScrollableTabBody(child: queuePanel),
                    if (conversionPanel != null)
                      _ScrollableTabBody(child: conversionPanel!),
                    _ScrollableTabBody(child: historyPanel),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrollableTabBody extends StatefulWidget {
  const _ScrollableTabBody({required this.child});

  final Widget child;

  @override
  State<_ScrollableTabBody> createState() => _ScrollableTabBodyState();
}

class _ScrollableTabBodyState extends State<_ScrollableTabBody> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(10),
        child: widget.child,
      ),
    );
  }
}
