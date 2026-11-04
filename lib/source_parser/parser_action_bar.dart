import 'package:flutter/material.dart';

class ParserActionBar extends StatelessWidget {
  const ParserActionBar({
    super.key,
    required this.hints,
    required this.isParsing,
    required this.onOpenBrowser,
    required this.onParse,
  });

  final Widget hints;
  final bool isParsing;
  final VoidCallback onOpenBrowser;
  final VoidCallback onParse;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final actions = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('open-in-browser-button'),
            onPressed: onOpenBrowser,
            icon: const Icon(Icons.open_in_browser),
            label: const Text('在浏览器打开'),
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
      if (constraints.maxWidth < 480) {
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
