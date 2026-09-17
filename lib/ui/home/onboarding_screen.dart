import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../brand_mark.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.app,
    required this.onContinue,
  });

  final AppController app;
  final Future<void> Function(String name) onContinue;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onContinue(_nameController.text);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Could not save your name. Check your device storage and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            key: const Key('onboarding-scroll-view'),
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 540,
                  minHeight: (constraints.maxHeight - 60).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: const MeowWatchMark(size: 54),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Close the distance.\nKeep the movie night.',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontFamily: 'DMSerifDisplay',
                        fontSize: 40,
                        fontWeight: FontWeight.w400,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Watch in sync, react together, and carry the same room from your phone to the big screen.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 34),
                    TextField(
                      key: const Key('display-name-field'),
                      controller: _nameController,
                      enabled: !_busy,
                      maxLength: 24,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.nickname],
                      decoration: InputDecoration(
                        labelText: 'Display name (optional)',
                        helperText:
                            'Leave blank to continue as ${widget.app.username}.',
                        helperMaxLines: 2,
                        errorText: _error,
                        errorMaxLines: 3,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _continue(),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        key: const Key('onboarding-continue-button'),
                        onPressed: _busy ? null : _continue,
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Continue'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'No account needed. Change your name anytime.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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
