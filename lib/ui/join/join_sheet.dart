import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../core/session/room_invite.dart';

Future<String?> showJoinSheet(
  BuildContext context, {
  required AppController app,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _JoinSheet(app: app),
  );
}

class _JoinSheet extends StatefulWidget {
  const _JoinSheet({required this.app});

  final AppController app;

  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _error;
  bool _pasting = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    if (_pasting) return;
    setState(() => _pasting = true);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final value = data?.text?.trim() ?? '';
      setState(() {
        if (value.isEmpty) {
          _error = 'There is no room code or invite link on your clipboard.';
        } else {
          _controller.text = value;
          _controller.selection = TextSelection.collapsed(offset: value.length);
          _error = null;
        }
      });
      if (value.isNotEmpty) _focusNode.requestFocus();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Could not read the clipboard. Paste or type the invite instead.';
        });
      }
    } finally {
      if (mounted) setState(() => _pasting = false);
    }
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Enter the room code your friend shared.');
      _focusNode.requestFocus();
      return;
    }
    try {
      parseRoomInvite(value, widget.app.username);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      _focusNode.requestFocus();
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        key: const Key('join-sheet-scroll-view'),
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Join their movie night',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Paste a MeowWatch invite link or enter the room code they sent you.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                TextField(
                  key: const Key('join-code-field'),
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  maxLength: 512,
                  maxLines: 2,
                  minLines: 1,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Room code or invite link',
                    hintText: 'quiet-otter-lantern',
                    errorText: _error,
                    errorMaxLines: 3,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      key: const Key('paste-invite-button'),
                      tooltip: 'Paste from clipboard',
                      onPressed: _pasting ? null : _paste,
                      icon: const Icon(Icons.content_paste_rounded),
                    ),
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    key: const Key('join-submit-button'),
                    onPressed: _submit,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Join room'),
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
