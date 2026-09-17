import 'package:flutter/material.dart';

import '../app_theme.dart';

Future<void> showAppearanceSheet(
  BuildContext context, {
  required String currentTheme,
  required bool isPlus,
  required Future<void> Function(String) onSelect,
  required VoidCallback onUpgrade,
}) async {
  final pageRoute = ModalRoute.of(context);
  if (pageRoute?.isCurrent != true) return;
  final navigator = Navigator.of(context);
  ModalRoute<bool>? sheetRoute;
  final upgradeRequested = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final route = ModalRoute.of<bool>(context)!;
      sheetRoute = route;
      return AppearanceSheet(
        currentTheme: currentTheme,
        isPlus: isPlus,
        onSelect: onSelect,
        onUpgrade: () {
          if (route.isActive && route.isCurrent) navigator.pop(true);
        },
      );
    },
  );
  // A pop result arrives before the sheet removes its overlay entries.
  await sheetRoute?.completed;
  if (upgradeRequested == true &&
      context.mounted &&
      navigator.mounted &&
      pageRoute?.isActive == true &&
      pageRoute?.isCurrent == true) {
    onUpgrade();
  }
}

class AppearanceSheet extends StatefulWidget {
  const AppearanceSheet({
    super.key,
    required this.currentTheme,
    required this.isPlus,
    required this.onSelect,
    required this.onUpgrade,
  });

  final String currentTheme;
  final bool isPlus;
  final Future<void> Function(String) onSelect;
  final VoidCallback onUpgrade;

  @override
  State<AppearanceSheet> createState() => _AppearanceSheetState();
}

class _AppearanceSheetState extends State<AppearanceSheet> {
  late String _selected;
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _selected = normalizeMeowWatchTheme(widget.currentTheme);
  }

  @override
  void didUpdateWidget(AppearanceSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTheme != widget.currentTheme) {
      _selected = normalizeMeowWatchTheme(widget.currentTheme);
    }
  }

  Future<void> _select(String id) async {
    if (_saving) return;
    if (id != 'cozy' && !widget.isPlus) {
      widget.onUpgrade();
      return;
    }
    if (id == _selected) return;
    setState(() {
      _saving = true;
      _message = 'Saving theme…';
    });
    try {
      await widget.onSelect(id);
      if (!mounted) return;
      setState(() {
        _selected = id;
        _message = '${_themeName(id)} applied.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not save your theme. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _close() {
    final route = ModalRoute.of(context);
    if (route?.isActive == true && route?.isCurrent == true) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: (media.size.height - media.viewInsets.bottom) * 0.94,
        ),
        child: Material(
          color: scheme.surface,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: SingleChildScrollView(
            key: const Key('appearance-scroll-view'),
            padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + media.padding.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Appearance',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close appearance',
                      onPressed: _saving ? null : _close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  'Set the mood for movie night.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                for (final id in meowWatchThemeIds) ...[
                  _ThemeChoice(
                    id: id,
                    selected: id == _selected,
                    locked: id != 'cozy' && !widget.isPlus,
                    saving: _saving,
                    onTap: () => _select(id),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_message != null)
                  Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_message!),
                    ),
                  ),
                Text(
                  widget.isPlus
                      ? 'All three themes are included with your Plus membership.'
                      : 'Cozy is free. Cinema Noir and Glass Aurora are included with MeowWatch Plus.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.id,
    required this.selected,
    required this.locked,
    required this.saving,
    required this.onTap,
  });

  final String id;
  final bool selected;
  final bool locked;
  final bool saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = meowWatchTheme(theme: id);
    final scheme = theme.colorScheme;
    return Theme(
      data: theme,
      child: Semantics(
        selected: selected,
        button: true,
        enabled: !saving,
        excludeSemantics: true,
        label: '${_themeName(id)}${locked ? ', requires Plus' : ''}',
        onTap: saving ? null : onTap,
        child: Material(
          color: scheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('theme-choice-$id'),
            onTap: saving ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _themeName(id),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (locked)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 18,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Plus',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        )
                      else
                        Icon(
                          selected ? Icons.check_circle : Icons.circle_outlined,
                          color: selected ? scheme.primary : scheme.outline,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _themeDescription(id),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ExcludeSemantics(
                    child: DecoratedBox(
                      key: Key('theme-preview-$id'),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: scheme.onPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Movie night',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  Text(
                                    'Theme preview',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

String _themeName(String id) => switch (id) {
  'cinemaNoir' => 'Cinema Noir',
  'glassAurora' => 'Glass Aurora',
  _ => 'Cozy',
};

String _themeDescription(String id) => switch (id) {
  'cinemaNoir' => 'Quiet charcoal and soft champagne.',
  'glassAurora' => 'Cool blue and soft mint.',
  _ => 'Warm apricot and soft navy.',
};
