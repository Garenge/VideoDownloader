import 'package:flutter/material.dart';

class DownloadTasksPage extends StatelessWidget {
  const DownloadTasksPage({
    super.key,
    required this.activity,
    required this.queueBuilder,
    required this.historyBuilder,
    this.conversionBuilder,
  });

  final Listenable activity;
  final WidgetBuilder queueBuilder;
  final WidgetBuilder historyBuilder;
  final WidgetBuilder? conversionBuilder;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: conversionBuilder == null ? 2 : 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('下载任务'),
        bottom: TabBar(
          tabs: [
            const Tab(text: '队列'),
            const Tab(text: '历史'),
            if (conversionBuilder != null) const Tab(text: '转换'),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: activity,
        builder: (context, _) => TabBarView(
          children: [
            _scrollPanel(context, queueBuilder),
            _scrollPanel(context, historyBuilder),
            if (conversionBuilder != null)
              _scrollPanel(context, conversionBuilder!),
          ],
        ),
      ),
    ),
  );

  Widget _scrollPanel(BuildContext context, WidgetBuilder builder) =>
      SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: builder(context),
      );
}
