import 'package:flutter/material.dart';

Future<void> showQuickGuideSheet(BuildContext context) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (_) => const QuickGuideSheet(),
  );
}

class QuickGuideSheet extends StatefulWidget {
  const QuickGuideSheet({super.key});

  @override
  State<QuickGuideSheet> createState() => _QuickGuideSheetState();
}

class _QuickGuideSheetState extends State<QuickGuideSheet> {
  static const _steps = [
    (
      icon: Icons.video_library_outlined,
      title: 'Pick your video',
      body:
          'Open a video on this device or paste a direct video link. '
          'Just watching on your own? Choose Local mode.',
      note:
          'Use a video file or a direct media link. Webpages and protected '
          'streaming services are not supported.',
    ),
    (
      icon: Icons.people_outline,
      title: 'Bring a friend',
      body:
          'Start a room and share its invite, or join with a friend’s invite '
          'code. Each person opens the same video on their own device.',
      note:
          'MeowWatch syncs playback, not the video file. For local videos, '
          'everyone needs their own copy.',
    ),
    (
      icon: Icons.play_circle_outline,
      title: 'Press play together',
      body:
          'Once everyone has their video ready, play, pause and seek stay '
          'in sync. Chat and send reactions while you watch.',
      note:
          'Free includes one new hosted session per local day. Joining '
          'friends and Local mode stay free.',
    ),
  ];

  final _scroll = ScrollController();
  int _page = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    setState(() => _page = page);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final step = _steps[_page];
    final last = _page == _steps.length - 1;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight:
                (media.size.height - media.viewInsets.bottom).clamp(
                  0,
                  double.infinity,
                ) *
                0.94,
          ),
          child: Material(
            key: const Key('quick-guide-sheet'),
            color: colors.surface,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Quick guide',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        key: const Key('quick-guide-close'),
                        tooltip: 'Close guide',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (var i = 0; i < _steps.length; i++)
                        Expanded(
                          child: Container(
                            margin: EdgeInsets.only(right: i == 2 ? 0 : 6),
                            height: 4,
                            decoration: BoxDecoration(
                              color: i <= _page
                                  ? colors.primary
                                  : colors.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainer,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(step.icon, size: 34, color: colors.primary),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Step ${_page + 1} of ${_steps.length}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(step.title, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 14),
                  Text(
                    step.body,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      step.note,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (_page > 0) ...[
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('quick-guide-back'),
                            onPressed: () => _goTo(_page - 1),
                            child: const Text('Back'),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: FilledButton(
                          key: const Key('quick-guide-next'),
                          onPressed: last
                              ? () => Navigator.of(context).pop()
                              : () => _goTo(_page + 1),
                          child: Text(last ? 'Got it' : 'Next'),
                        ),
                      ),
                    ],
                  ),
                  if (!last)
                    TextButton(
                      key: const Key('quick-guide-skip'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Skip guide'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
