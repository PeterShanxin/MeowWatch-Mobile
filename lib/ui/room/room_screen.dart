import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../app/app_controller.dart';
import '../../core/playback/local_mobile_target.dart';
import '../../core/playback/playback_target.dart';
import '../../core/sync/peer_state.dart';
import '../chat/chat_panel.dart';

String formatPlaybackTime(Duration value) {
  final seconds = value.inSeconds.clamp(0, 359999);
  final minutes = seconds ~/ 60;
  return minutes >= 60
      ? '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}'
      : '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
}

class RoomScreen extends StatelessWidget {
  const RoomScreen({
    super.key,
    required this.app,
    required this.onLoad,
    required this.onInvite,
    required this.onDevices,
    required this.onLeave,
    required this.onStartRoom,
    required this.onTogglePlay,
    required this.onSeek,
  });
  final AppController app;
  final VoidCallback onLoad,
      onInvite,
      onDevices,
      onLeave,
      onStartRoom,
      onTogglePlay;
  final ValueChanged<Duration> onSeek;

  String get _connectionLabel => switch (app.connection.status) {
    SyncConnectionStatus.connected =>
      app.peers.isEmpty ? 'Waiting for your people' : 'Together in this room',
    SyncConnectionStatus.connecting ||
    SyncConnectionStatus.handshaking => 'Joining securely…',
    SyncConnectionStatus.reconnecting => 'Reconnecting · playback paused',
    _ => 'Connection lost · playback paused',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tablet =
                constraints.maxWidth >= 700 && constraints.maxHeight >= 500;
            final twoColumn =
                constraints.maxWidth >= 900 && constraints.maxHeight >= 500;
            final landscape =
                constraints.maxWidth > constraints.maxHeight && !twoColumn;
            final header = Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: onLeave,
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: app.isLocal ? 'Back to home' : 'Leave room',
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.isNearby
                              ? app.nearby!.label
                              : app.isCasting
                              ? app.cast!.receiverName
                              : app.isLocal
                              ? 'Your own screening'
                              : app.room!.config.room,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          app.isNearby
                              ? app.nearby!.connected
                                    ? 'Playing on nearby desktop'
                                    : 'Desktop disconnected'
                              : app.isCasting
                              ? app.cast!.connected
                                    ? 'Playing on your TV'
                                    : 'TV disconnected'
                              : app.isLocal
                              ? 'Local mode'
                              : _connectionLabel,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onDevices,
                    icon: const Icon(Icons.devices_rounded),
                    tooltip: 'Choose playback screen',
                  ),
                  if (!app.isLocal)
                    IconButton(
                      onPressed: onInvite,
                      icon: const Icon(Icons.ios_share_rounded),
                      tooltip: 'Invite to room',
                    ),
                ],
              ),
            );
            final controls = _PlaybackControls(
              app: app,
              onToggle: onTogglePlay,
              onSeek: onSeek,
              compact: landscape,
            );
            final stage = _VideoStage(
              app: app,
              onLoad: onLoad,
              onDevices: onDevices,
            );
            if (landscape) {
              return Stack(
                children: [
                  Positioned.fill(child: stage),
                  Align(
                    alignment: Alignment.topCenter,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: .76),
                      child: header,
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: .76),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(flex: 3, child: controls),
                          Flexible(
                            flex: 2,
                            child: _Actions(
                              app: app,
                              onLoad: onLoad,
                              onStartRoom: onStartRoom,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            final player = Column(
              children: [
                header,
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.symmetric(horizontal: tablet ? 28 : 20),
                    children: [
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: AspectRatio(aspectRatio: 16 / 10, child: stage),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        app.target.snapshot.media?.title ??
                            (app.isNearby
                                ? 'Ready when your desktop is.'
                                : app.isLocal
                                ? 'Settle in.'
                                : 'The best seat is together.'),
                        style: Theme.of(context).textTheme.headlineMedium,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        app.target.snapshot.media == null
                            ? app.isNearby
                                  ? 'Choose this video’s file on your desktop. Phone files are not transferred.'
                                  : 'Choose a video file or open a direct video link.'
                            : 'Playing on ${app.target.label.toLowerCase()}',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      if (!app.isLocal) ...[
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _Person(name: app.username, self: true),
                            ...app.peers.map((name) => _Person(name: name)),
                          ],
                        ),
                        if (app.peers.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: OutlinedButton.icon(
                              onPressed: onInvite,
                              icon: const Icon(Icons.link_rounded),
                              label: const Text('Invite someone'),
                            ),
                          ),
                        if (!tablet && app.messages.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: InkWell(
                              onTap: () => showChatSheet(context, app),
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      color: colors.secondary,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        app.messages.last.text,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right_rounded),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                controls,
                _Actions(app: app, onLoad: onLoad, onStartRoom: onStartRoom),
              ],
            );
            return twoColumn
                ? Row(
                    children: [
                      Expanded(child: player),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 340,
                        child: app.isLocal
                            ? _LocalInvitation(onStartRoom: onStartRoom)
                            : ChatPanel(app: app),
                      ),
                    ],
                  )
                : tablet
                ? Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: player,
                    ),
                  )
                : player;
          },
        ),
      ),
    );
  }
}

class _VideoStage extends StatelessWidget {
  const _VideoStage({
    required this.app,
    required this.onLoad,
    required this.onDevices,
  });
  final AppController app;
  final VoidCallback onLoad, onDevices;
  @override
  Widget build(BuildContext context) {
    final target = app.target;
    final state = target.snapshot;
    final controller = target is LocalMobileTarget ? target.controller : null;
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;
    return ColoredBox(
      color: const Color(0xFF070B12),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (controller != null && state.ready)
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            )
          else if (state.connection == PlaybackConnection.loading)
            const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Opening your video…'),
              ],
            )
          else if (app.isNearby || app.isCasting)
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    app.isCasting
                        ? Icons.cast_connected_rounded
                        : Icons.desktop_windows_outlined,
                    size: 46,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.error ??
                        (app.isCasting
                            ? 'Watching on ${app.cast!.receiverName}'
                            : state.media == null
                            ? 'Choose this video’s file on your desktop'
                            : state.ready
                            ? 'Watching on ${app.nearby!.label}'
                            : 'Reconnect to the desktop to keep watching'),
                    textAlign: TextAlign.center,
                  ),
                  if (app.isNearby && state.media == null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Local phone files stay on this device.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: onDevices,
                    icon: const Icon(Icons.devices_rounded),
                    label: const Text('Choose screen'),
                  ),
                ],
              ),
            )
          else
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    state.error == null
                        ? Icons.movie_outlined
                        : Icons.info_outline_rounded,
                    size: 46,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  if (state.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(state.error!, textAlign: TextAlign.center),
                    ),
                  if (largeText)
                    FilledButton.tonal(
                      onPressed: onLoad,
                      child: Text(
                        state.error == null
                            ? 'Choose a video'
                            : 'Choose another video',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: onLoad,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(
                        state.error == null
                            ? 'Choose a video'
                            : 'Choose another video',
                      ),
                    ),
                ],
              ),
            ),
          if (state.buffering && state.ready && state.playing)
            const CircularProgressIndicator(),
          if (app.reaction != null)
            Positioned(
              right: 24,
              bottom: 20,
              child: Semantics(
                label:
                    '${app.reaction!.username} reacted ${app.reaction!.emoji}',
                child: Text(
                  app.reaction!.emoji,
                  style: const TextStyle(fontSize: 60),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaybackControls extends StatefulWidget {
  const _PlaybackControls({
    required this.app,
    required this.onToggle,
    required this.onSeek,
    this.compact = false,
  });
  final AppController app;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;
  final bool compact;
  @override
  State<_PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends State<_PlaybackControls> {
  double? _drag;
  @override
  Widget build(BuildContext context) {
    final state = widget.app.target.snapshot;
    final ready = state.ready && (widget.app.isLocal || widget.app.isConnected);
    final maximum = state.duration.inMilliseconds.toDouble().clamp(
      1.0,
      double.infinity,
    );
    final position = (_drag ?? state.position.inMilliseconds.toDouble()).clamp(
      0.0,
      maximum,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, widget.compact ? 0 : 8, 20, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (widget.compact)
                IconButton.filled(
                  onPressed: ready ? widget.onToggle : null,
                  icon: Icon(
                    state.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  tooltip: state.playing ? 'Pause together' : 'Play together',
                ),
              Expanded(
                child: Slider(
                  value: position,
                  max: maximum,
                  onChanged: ready
                      ? (value) => setState(() => _drag = value)
                      : null,
                  onChangeEnd: ready
                      ? (value) {
                          setState(() => _drag = null);
                          widget.onSeek(Duration(milliseconds: value.round()));
                        }
                      : null,
                  semanticFormatterCallback: (value) =>
                      formatPlaybackTime(Duration(milliseconds: value.round())),
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  formatPlaybackTime(Duration(milliseconds: position.round())),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  formatPlaybackTime(state.duration),
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
          if (!widget.compact)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: ready
                        ? () => widget.onSeek(
                            state.position - const Duration(seconds: 10),
                          )
                        : null,
                    icon: const Icon(Icons.replay_10_rounded),
                    tooltip: 'Back 10 seconds',
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      minimumSize: const Size(64, 56),
                    ),
                    onPressed: ready ? widget.onToggle : null,
                    iconSize: 34,
                    icon: Icon(
                      state.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    tooltip: state.playing ? 'Pause' : 'Play',
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: ready
                        ? () => widget.onSeek(
                            state.position + const Duration(seconds: 10),
                          )
                        : null,
                    icon: const Icon(Icons.forward_10_rounded),
                    tooltip: 'Forward 10 seconds',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.app,
    required this.onLoad,
    required this.onStartRoom,
  });
  final AppController app;
  final VoidCallback onLoad, onStartRoom;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        TextButton.icon(
          onPressed: app.isNearby ? null : onLoad,
          icon: const Icon(Icons.video_library_outlined),
          label: Text(app.isNearby ? 'Choose on desktop' : 'Video'),
        ),
        if (app.isLocal)
          TextButton.icon(
            onPressed: onStartRoom,
            icon: const Icon(Icons.people_outline_rounded),
            label: const Text('Watch together'),
          )
        else ...[
          TextButton.icon(
            onPressed: () => showChatSheet(context, app),
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('Chat'),
          ),
          IconButton(
            onPressed: app.isConnected ? () => _reactions(context) : null,
            icon: const Icon(Icons.favorite_border_rounded),
            tooltip: 'Send a reaction',
          ),
        ],
      ],
    ),
  );

  Future<void> _reactions(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: ['❤️', '😂', '😮', '👏', '🍿']
            .map(
              (emoji) => Semantics(
                label: 'React $emoji',
                button: true,
                child: TextButton(
                  onPressed: () {
                    app.sendReaction(emoji);
                    HapticFeedback.selectionClick();
                    Navigator.pop(context);
                  },
                  child: Text(emoji, style: const TextStyle(fontSize: 32)),
                ),
              ),
            )
            .toList(),
      ),
    ),
  );
}

class _Person extends StatelessWidget {
  const _Person({required this.name, this.self = false});
  final String name;
  final bool self;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 240),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          child: Text(name.characters.take(1).toString()),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            self ? '$name (you)' : name,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

class _LocalInvitation extends StatelessWidget {
  const _LocalInvitation({required this.onStartRoom});
  final VoidCallback onStartRoom;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.weekend_outlined, size: 54),
          const SizedBox(height: 24),
          Text(
            'Room for one more.',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Turn this screening into a shared movie night.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onStartRoom,
            child: const Text('Start a room'),
          ),
        ],
      ),
    ),
  );
}
