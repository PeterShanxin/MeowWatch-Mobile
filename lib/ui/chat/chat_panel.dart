import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/sync/peer_state.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key, required this.app, this.onClose});
  final AppController app;
  final VoidCallback? onClose;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _text = TextEditingController();
  @override
  void dispose() {
    widget.app.sendTyping(false);
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final message = _text.text.trim();
    if (message.isEmpty || !widget.app.isConnected) return;
    widget.app.sendChat(message);
    widget.app.sendTyping(false);
    _text.clear();
  }

  String? _connectionMessage(AppController app) =>
      switch (app.connection.status) {
        SyncConnectionStatus.connecting ||
        SyncConnectionStatus.handshaking => 'Joining chat securely…',
        SyncConnectionStatus.reconnecting =>
          'Reconnecting. Messages are paused for a moment.',
        SyncConnectionStatus.disconnected || SyncConnectionStatus.error =>
          'Chat is offline. Reconnect to send a message.',
        SyncConnectionStatus.connected => null,
      };

  bool _isLoading(AppController app) =>
      app.connection.status == SyncConnectionStatus.connecting ||
      app.connection.status == SyncConnectionStatus.handshaking ||
      app.connection.status == SyncConnectionStatus.reconnecting;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.app,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final app = widget.app;
        final colors = Theme.of(context).colorScheme;
        final compact = constraints.maxHeight < 280;
        final connectionMessage = _connectionMessage(app);
        return Column(
          children: [
            Padding(
              padding: compact
                  ? const EdgeInsets.fromLTRB(12, 0, 4, 0)
                  : const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: connectionMessage == null
                          ? 'Room chat'
                          : 'Room chat. $connectionMessage',
                      liveRegion: connectionMessage != null,
                      excludeSemantics: true,
                      child: Text(
                        'Room chat',
                        style: compact
                            ? Theme.of(context).textTheme.titleMedium
                            : Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  if (widget.onClose != null)
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close),
                      tooltip: 'Close chat',
                    ),
                ],
              ),
            ),
            if (connectionMessage != null && !compact)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Semantics(
                  liveRegion: true,
                  child: Row(
                    children: [
                      if (_isLoading(app))
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 20,
                          color: colors.onSurfaceVariant,
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          connectionMessage,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: app.messages.isEmpty
                  ? SingleChildScrollView(
                      padding: EdgeInsets.all(compact ? 8 : 28),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!compact) ...[
                              Icon(
                                app.isConnected
                                    ? Icons.chat_bubble_outline_rounded
                                    : Icons.forum_outlined,
                                color: colors.secondary,
                              ),
                              const SizedBox(height: 12),
                            ],
                            Text(
                              app.isConnected
                                  ? 'No messages yet. Say hello.'
                                  : compact
                                  ? 'Messages return after reconnecting.'
                                  : 'Messages will appear here when chat reconnects.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(20),
                      itemCount: app.messages.length,
                      itemBuilder: (context, index) {
                        final item =
                            app.messages[app.messages.length - 1 - index];
                        if (item.system) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              item.text,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          );
                        }
                        return Align(
                          alignment: item.isMine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 300),
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: item.isMine
                                  ? colors.primaryContainer
                                  : colors.surfaceContainer,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!item.isMine)
                                  Text(
                                    item.username,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(color: colors.secondary),
                                  ),
                                Text(
                                  item.text,
                                  style: TextStyle(
                                    color: item.isMine
                                        ? colors.onPrimaryContainer
                                        : colors.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (app.typing.isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${app.typing.keys.join(', ')} typing…',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            Padding(
              padding: compact
                  ? const EdgeInsets.fromLTRB(8, 2, 8, 4)
                  : const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      enabled: app.isConnected,
                      minLines: 1,
                      maxLines: compact ? 1 : 3,
                      maxLength: 150,
                      textInputAction: TextInputAction.send,
                      onChanged: (text) =>
                          app.sendTyping(text.trim().isNotEmpty),
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: app.isConnected
                            ? 'Say something…'
                            : 'Chat unavailable',
                        counterText: '',
                        isDense: compact,
                        contentPadding: compact
                            ? const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: app.isConnected ? _send : null,
                    icon: const Icon(Icons.arrow_upward_rounded),
                    tooltip: 'Send message',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> showChatSheet(BuildContext context, AppController app) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: math.min(
            MediaQuery.sizeOf(context).height *
                (MediaQuery.orientationOf(context) == Orientation.landscape
                    ? .9
                    : .65),
            math.max(
              0,
              MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom,
            ),
          ),
          child: ChatPanel(app: app, onClose: () => Navigator.pop(context)),
        ),
      ),
    );
