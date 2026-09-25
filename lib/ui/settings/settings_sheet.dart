import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_services.dart';
import '../../core/billing/billing_service.dart';
import '../help/quick_guide_sheet.dart';
import 'about_sheet.dart';
import 'appearance_sheet.dart';

Future<void> showSettingsSheet(
  BuildContext context, {
  required AppController app,
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
    barrierColor: Colors.black.withValues(alpha: 0.68),
    builder: (context) {
      final route = ModalRoute.of<bool>(context)!;
      sheetRoute = route;
      return _SettingsSheet(
        app: app,
        onUpgrade: () {
          if (route.isActive && route.isCurrent) navigator.pop(true);
        },
      );
    },
  );
  // Opening the paywall waits until this sheet releases its overlay entries.
  await sheetRoute?.completed;
  if (upgradeRequested == true &&
      context.mounted &&
      navigator.mounted &&
      pageRoute?.isActive == true &&
      pageRoute?.isCurrent == true) {
    onUpgrade();
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.app, required this.onUpgrade});

  final AppController app;
  final VoidCallback onUpgrade;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final TextEditingController _name;
  final GlobalKey _restoreFeedbackKey = GlobalKey();
  String? _message;
  String? _restoreMessage;
  bool _working = false;

  BillingService get _billing => widget.app.billing;
  bool get _inRoom => widget.app.room != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.app.username);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    setState(() {
      _working = true;
      _message = null;
      _restoreMessage = null;
    });
    try {
      await widget.app.setName(_name.text);
      _name.text = widget.app.username;
      if (mounted) setState(() => _message = 'Display name saved.');
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Could not save your display name.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _working = true;
      _message = null;
      _restoreMessage = null;
    });
    BillingResult result;
    if (!_billing.isConfigured) {
      result = await _billing.configure();
      if (result.succeeded) {
        result = await _billing.restore();
      }
    } else {
      result = await _billing.restore();
    }
    if (!mounted) return;
    setState(() {
      _working = false;
      _restoreMessage = !result.succeeded
          ? (result.message ?? 'Could not restore purchases right now.')
          : _billing.isPlus
          ? 'Restored. MeowWatch Plus is active.'
          : 'No active Plus purchase was found for this store account.';
    });
    await WidgetsBinding.instance.endOfFrame;
    final feedback = _restoreFeedbackKey.currentContext;
    if (mounted && feedback != null) {
      await Scrollable.ensureVisible(
        feedback,
        alignment: 0.8,
        duration: const Duration(milliseconds: 200),
      );
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          backgroundColor: colors.surfaceContainer,
          title: Text(
            'Clear watch history?',
            style: TextStyle(color: colors.onSurface),
          ),
          content: Text(
            'This removes saved videos and resume positions from this device.',
            style: TextStyle(color: colors.onSurface),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep history'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _working = true;
      _message = null;
      _restoreMessage = null;
    });
    try {
      final keys = widget.app.repository.history
          .map((entry) => entry.key)
          .toList(growable: false);
      for (final key in keys) {
        await widget.app.repository.removeHistory(key);
      }
      if (mounted) setState(() => _message = 'Watch history cleared.');
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not clear watch history.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _close() {
    final route = ModalRoute.of(context);
    if (route?.isActive == true && route?.isCurrent == true) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _appearance() async {
    await showAppearanceSheet(
      context,
      currentTheme: widget.app.theme,
      isPlus: _billing.isPlus,
      onSelect: widget.app.selectTheme,
      onUpgrade: widget.onUpgrade,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = Theme.of(context).colorScheme;
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
            color: colors.surface,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: AnimatedBuilder(
              animation: widget.app,
              builder: (context, _) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Settings',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          onPressed: _working || _billing.isBusy
                              ? null
                              : _close,
                          icon: Icon(Icons.close, color: colors.onSurface),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _Section(
                      title: 'Your name',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _name,
                            enabled: !_inRoom && !_working,
                            maxLength: 24,
                            textInputAction: TextInputAction.done,
                            style: TextStyle(color: colors.onSurface),
                            cursorColor: colors.primary,
                            onChanged: (_) => setState(() {
                              _message = null;
                              _restoreMessage = null;
                            }),
                            onSubmitted: (_) {
                              if (!_inRoom && !_working) _saveName();
                            },
                            decoration: InputDecoration(
                              labelText: 'Display name',
                              labelStyle: TextStyle(
                                color: colors.onSurface.withValues(alpha: 0.62),
                              ),
                              helperText: _inRoom
                                  ? 'Leave the current room before changing your name.'
                                  : 'Leave blank for a new friendly name.',
                              helperMaxLines: 2,
                              filled: true,
                              fillColor: colors.surface,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: colors.onSurface.withValues(
                                    alpha: 0.22,
                                  ),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: colors.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: colors.surface,
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _inRoom || _working ? null : _saveName,
                            child: const Text('Save name'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Section(
                      title: 'MeowWatch Plus',
                      child: Column(
                        key: const Key('settings-plus-content'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _billing.isPlus
                                    ? Icons.check_circle
                                    : Icons.nightlight_outlined,
                                color: _billing.isPlus
                                    ? colors.primary
                                    : colors.secondary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _billing.isPlus
                                      ? 'Plus is active · unlimited hosting'
                                      : 'Free · one new hosted session per local day',
                                  style: TextStyle(
                                    color: colors.onSurface,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (usesTestStore) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Connected to RevenueCat Test Store (sandbox).',
                              style: TextStyle(color: colors.secondary),
                            ),
                          ],
                          if (!_billing.isPlus) ...[
                            const SizedBox(height: 14),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.primary,
                                foregroundColor: colors.surface,
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: _working || _billing.isBusy
                                  ? null
                                  : widget.onUpgrade,
                              child: const Text('See Plus'),
                            ),
                          ],
                          const SizedBox(height: 6),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: colors.secondary,
                              minimumSize: const Size.fromHeight(48),
                            ),
                            onPressed: _working || _billing.isBusy
                                ? null
                                : _restore,
                            child: const Text('Restore purchases'),
                          ),
                          if (_restoreMessage != null) ...[
                            const SizedBox(height: 8),
                            Semantics(
                              key: _restoreFeedbackKey,
                              liveRegion: true,
                              child: Text(
                                _restoreMessage!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.primary,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Section(
                      title: 'Appearance',
                      child: OutlinedButton.icon(
                        key: const Key('choose-appearance-button'),
                        onPressed: _working || _billing.isBusy
                            ? null
                            : _appearance,
                        icon: const Icon(Icons.palette_outlined),
                        label: const Text('Make yourself at home'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Section(
                      title: 'Help',
                      child: OutlinedButton.icon(
                        key: const Key('settings-quick-guide-button'),
                        onPressed: _working || _billing.isBusy
                            ? null
                            : () => showQuickGuideSheet(context),
                        icon: const Icon(Icons.explore_outlined),
                        label: const Text('Replay the quick guide'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _Section(
                      title: 'Privacy & data',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Your watch history stays in this app’s local '
                            'storage. Together Rooms, RevenueCat and paired '
                            'Nearby desktops each receive the data needed for '
                            'their feature.',
                            style: TextStyle(
                              color: colors.onSurface.withValues(alpha: 0.76),
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const Key('about-privacy-licenses-button'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.onSurface,
                              minimumSize: const Size.fromHeight(48),
                              side: BorderSide(
                                color: colors.onSurface.withValues(alpha: 0.28),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _working || _billing.isBusy
                                ? null
                                : () => showAboutSheet(context),
                            icon: const Icon(Icons.info_outline),
                            label: const Text('About, privacy & licenses'),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.onSurface,
                              minimumSize: const Size.fromHeight(48),
                              side: BorderSide(
                                color: colors.onSurface.withValues(alpha: 0.28),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed:
                                _working ||
                                    widget.app.repository.history.isEmpty
                                ? null
                                : _clearHistory,
                            icon: const Icon(Icons.delete_outline),
                            label: Text(
                              widget.app.repository.history.isEmpty
                                  ? 'Watch history is empty'
                                  : 'Clear watch history',
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_working || _billing.isBusy) ...[
                      const SizedBox(height: 18),
                      Center(
                        child: CircularProgressIndicator(color: colors.primary),
                      ),
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 18),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _message!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.primary, height: 1.35),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
