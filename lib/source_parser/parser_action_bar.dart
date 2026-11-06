import 'package:flutter/material.dart';

class ParserActionBar extends StatelessWidget {
  const ParserActionBar({
    super.key,
    required this.hints,
    required this.isParsing,
    required this.onOpenBrowser,
    required this.onParse,
    required this.onRecent,
  });

  final Widget hints;
  final bool isParsing;
  final VoidCallback onOpenBrowser;
  final VoidCallback onParse;
  final VoidCallback onRecent;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 480;
      final actions = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (compact)
            IconButton(
              key: const ValueKey('open-in-browser-button'),
              tooltip: '在浏览器打开',
              onPressed: onOpenBrowser,
              icon: const Icon(Icons.open_in_browser),
            )
          else
            OutlinedButton.icon(
              key: const ValueKey('open-in-browser-button'),
              onPressed: onOpenBrowser,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('在浏览器打开'),
            ),
          if (compact)
            IconButton(
              key: const ValueKey('open-recent-urls-button'),
              tooltip: '最近解析',
              onPressed: onRecent,
              icon: const Icon(Icons.history),
            )
          else
            OutlinedButton.icon(
              key: const ValueKey('open-recent-urls-button'),
              onPressed: onRecent,
              icon: const Icon(Icons.history),
              label: const Text('最近'),
            ),
          FilledButton.icon(
            onPressed: isParsing ? null : onParse,
            icon: isParsing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(isParsing ? '解析中' : '解析'),
          ),
        ],
      );
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [hints, const SizedBox(height: 12), actions],
        );
      }
      return Row(
        children: [
          Expanded(child: hints),
          const SizedBox(width: 14),
          actions,
        ],
      );
    },
  );
}
