import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_controller.dart';
import '../../core/connect/room_config.dart';
import '../../core/session/room_invite.dart';
import '../shared/invitation_scanner.dart';

Future<String?> showJoinSheet(
  BuildContext context, {
  required AppController app,
  String? initialInvite,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (context) => _JoinSheet(app: app, initialInvite: initialInvite),
  );
}

class _JoinSheet extends StatefulWidget {
  const _JoinSheet({required this.app, this.initialInvite});

  final AppController app;
  final String? initialInvite;

  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _fieldVisibilityKey = GlobalKey();
  String? _error;
  bool _pasting = false;
  bool _scanning = false;
  bool _scannedInvite = false;

  bool get _isIncomingInvite => widget.initialInvite != null || _scannedInvite;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialInvite ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    if (_pasting || _scanning) return;
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

  Future<void> _scan() async {
    if (_scanning || _pasting) return;
    setState(() => _scanning = true);
    try {
      final invitation = await scanRoomInvitation(context);
      if (!mounted || invitation == null) return;
      setState(() {
        _controller.text = invitation;
        _controller.selection = TextSelection.collapsed(
          offset: invitation.length,
        );
        _scannedInvite = true;
        _error = null;
      });
      _focusNode.unfocus();
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _submit() {
    if (_scanning) return;
    final value = _controller.text.trim();
    if (value.isEmpty) {
      _showInputError('Enter the room code your friend shared.');
      return;
    }
    try {
      parseRoomInvite(value, widget.app.username);
    } on FormatException catch (error) {
      _showInputError(error.message);
      return;
    }
    Navigator.of(context).pop(value);
  }

  void _showInputError(String message) {
    setState(() => _error = message);
    _focusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _error != message) return;
      final fieldContext = _fieldVisibilityKey.currentContext;
      if (fieldContext == null) return;
      // Focus may already belong to the field after scrolling to submit.
      // Reveal its error after layout, above even a short keyboard viewport.
      Scrollable.ensureVisible(
        fieldContext,
        alignment: 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  RoomConfig? _parsedIncomingConfig() {
    if (!_isIncomingInvite) return null;
    try {
      return parseRoomInvite(_controller.text, widget.app.username);
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final incomingConfig = _parsedIncomingConfig();
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        key: const Key('join-sheet-scroll-view'),
        hitTestBehavior: HitTestBehavior.deferToChild,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Let the handle scroll away with the heading so the keyboard
                // leaves enough room for both the input and its error.
                Center(
                  child: Semantics(
                    key: const Key('join-sheet-dismiss'),
                    container: true,
                    button: true,
                    label: MaterialLocalizations.of(
                      context,
                    ).modalBarrierDismissLabel,
                    onTap: () => Navigator.of(context).pop(),
                    // Let the outer BottomSheet handle pointer dragging while
                    // retaining this node's accessible dismiss action.
                    child: IgnorePointer(
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: Container(
                            width: 32,
                            height: 4,
                            decoration: BoxDecoration(
                              color:
                                  theme.bottomSheetTheme.dragHandleColor ??
                                  theme.colorScheme.onSurfaceVariant,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isIncomingInvite
                      ? 'Room invitation received'
                      : 'Join their movie night',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isIncomingInvite
                      ? 'Review the room and server, then choose whether to join.'
                      : 'Paste a MeowWatch invite link or enter the room code they sent you.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  key: _fieldVisibilityKey,
                  child: TextField(
                    key: const Key('join-code-field'),
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: !_isIncomingInvite,
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
                        onPressed: _pasting || _scanning ? null : _paste,
                        icon: const Icon(Icons.content_paste_rounded),
                      ),
                    ),
                    onChanged: (_) {
                      if (_error != null || _isIncomingInvite) {
                        setState(() => _error = null);
                      }
                    },
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('scan-room-invite-button'),
                    onPressed: _pasting || _scanning ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Scan invite QR'),
                  ),
                ),
                if (incomingConfig != null) ...[
                  const SizedBox(height: 4),
                  Semantics(
                    container: true,
                    label:
                        'Room ${incomingConfig.room}, server ${incomingConfig.server}, port ${incomingConfig.port}',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Room: ${incomingConfig.room}'),
                            const SizedBox(height: 4),
                            Text(
                              'Server: ${incomingConfig.server}:${incomingConfig.port}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    key: const Key('join-submit-button'),
                    onPressed: _submit,
                    icon: const Icon(Icons.login_rounded),
                    label: Text(
                      _isIncomingInvite ? 'Join this room' : 'Join room',
                    ),
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
