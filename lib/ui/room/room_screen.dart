import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../app/app_controller.dart';
import '../../core/chat/reaction_catalog.dart';
import '../../core/platform/immersive_mode.dart';
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

class RoomScreen extends StatefulWidget {
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
    this.onUpgrade,
  });
  final AppController app;
  final VoidCallback onLoad,
      onInvite,
      onDevices,
      onLeave,
      onStartRoom,
      onTogglePlay;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onUpgrade;

  @override
  RoomScreenState createState() => RoomScreenState();
}

class RoomScreenState extends State<RoomScreen> {
  static const _fullscreenDiagnostics = bool.fromEnvironment(
    'MEOWWATCH_FULLSCREEN_DIAGNOSTICS',
  );
  final _stageKey = GlobalKey();
  Timer? _hideControlsTimer;
  bool _fullscreen = false;
  bool _controlsVisible = true;
  bool _accessibleNavigation = false;
  bool _controlsFocused = false;
  bool _controlsPressed = false;
  bool _platformMayBeFullscreen = false;
  int _modeRevision = 0;
  VoidCallback? _dismissModeError;
  String? _lastDiagnosticState;

  AppController get app => widget.app;
  VoidCallback get onLoad => widget.onLoad;
  VoidCallback get onInvite => widget.onInvite;
  VoidCallback get onDevices => widget.onDevices;
  VoidCallback get onLeave => widget.onLeave;
  VoidCallback get onStartRoom => widget.onStartRoom;
  VoidCallback get onTogglePlay => widget.onTogglePlay;
  ValueChanged<Duration> get onSeek => widget.onSeek;
  VoidCallback? get onUpgrade => widget.onUpgrade;

  bool get _canEnterFullscreen {
    final target = app.target;
    return !app.isRestoringHistory &&
        target is LocalMobileTarget &&
        target.controller != null &&
        target.snapshot.ready;
  }

  bool get _keepControlsVisible =>
      _accessibleNavigation ||
      (_controlsFocused &&
          FocusManager.instance.highlightMode ==
              FocusHighlightMode.traditional) ||
      _controlsPressed ||
      app.isRestoringHistory ||
      !app.playRequested ||
      !app.target.snapshot.ready ||
      (!app.isLocal && !app.isConnected);

  void _logFullscreenState(String event, {bool force = false}) {
    if (!_fullscreenDiagnostics) return;
    final snapshot = app.target.snapshot;
    final state =
        'fullscreen=$_fullscreen visible=$_controlsVisible '
        'accessible=$_accessibleNavigation '
        'highlight=${FocusManager.instance.highlightMode.name} '
        'focused=$_controlsFocused pressed=$_controlsPressed '
        'playRequested=${app.playRequested} playing=${snapshot.playing} '
        'buffering=${snapshot.buffering} ready=${snapshot.ready} '
        'connected=${app.isLocal || app.isConnected} '
        'keep=$_keepControlsVisible timer=${_hideControlsTimer != null}';
    if (!force && state == _lastDiagnosticState) return;
    _lastDiagnosticState = state;
    debugPrint('MEOWWATCH_FULLSCREEN event=$event $state');
  }

  @override
  void initState() {
    super.initState();
    app.addListener(_appChanged);
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
  }

  void _highlightModeChanged(FocusHighlightMode mode) {
    if (!mounted) return;
    // Touch can change input modality without moving the focused control.
    setState(() {
      if (_fullscreen && mode == FocusHighlightMode.traditional) {
        _controlsVisible = true;
      }
      _updateControlsTimer(restart: true);
    });
  }

  @override
  void didUpdateWidget(RoomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != app) {
      oldWidget.app.removeListener(_appChanged);
      app.addListener(_appChanged);
      exitFullscreen();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    _updateControlsTimer();
    _logFullscreenState('dependencies', force: true);
  }

  void _appChanged() {
    if (!mounted) return;
    if (_fullscreen && app.target is! LocalMobileTarget) {
      exitFullscreen();
    } else {
      setState(_updateControlsTimer);
    }
  }

  void _updateControlsTimer({bool restart = false}) {
    if (!_fullscreen || _keepControlsVisible) {
      final hadTimer = _hideControlsTimer != null;
      _hideControlsTimer?.cancel();
      _hideControlsTimer = null;
      _controlsVisible = true;
      if (hadTimer) _logFullscreenState('timer_cancel', force: true);
      _logFullscreenState('state');
      return;
    }
    if (restart) {
      _hideControlsTimer?.cancel();
      _hideControlsTimer = null;
    }
    if (_controlsVisible && _hideControlsTimer == null) {
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        _hideControlsTimer = null;
        if (!mounted) return;
        if (!_fullscreen || _keepControlsVisible) {
          _logFullscreenState('timer_blocked', force: true);
          return;
        }
        setState(() => _controlsVisible = false);
        _logFullscreenState('timer_fire', force: true);
      });
      _logFullscreenState('timer_schedule', force: true);
    }
    _logFullscreenState('state');
  }

  void _enterFullscreen() {
    if (_fullscreen || !_canEnterFullscreen) return;
    setState(() {
      _fullscreen = true;
      _controlsVisible = true;
      _updateControlsTimer(restart: true);
    });
    _logFullscreenState('entry', force: true);
    _requestImmersiveMode(true);
  }

  /// Consumes Back before MainApp considers leaving the room.
  /// The layout changes synchronously, including during a pending entry.
  bool exitFullscreen() {
    if (!_fullscreen) return false;
    setState(() {
      _fullscreen = false;
      _controlsFocused = false;
      _controlsPressed = false;
      _updateControlsTimer();
    });
    _logFullscreenState('exit', force: true);
    _requestImmersiveMode(false);
    return true;
  }

  void _requestImmersiveMode(bool enabled) {
    final revision = ++_modeRevision;
    _clearModeError();
    if (enabled) _platformMayBeFullscreen = true;
    // Send every intent immediately. The platform bridge owns global ordering;
    // an old RoomScreen must never delay its exit until a new room has entered.
    unawaited(_applyImmersiveMode(enabled, revision));
  }

  Future<void> _applyImmersiveMode(bool enabled, int revision) async {
    try {
      await ImmersiveMode.setEnabled(
        enabled,
      ).timeout(const Duration(seconds: 5));
      if (revision != _modeRevision) return;
      _platformMayBeFullscreen = enabled;
    } catch (error) {
      if (revision != _modeRevision) return;
      if (!mounted) {
        debugPrint(
          'Could not restore system controls after player exit: $error',
        );
        return;
      }
      if (enabled) exitFullscreen();
      _showModeError(enabled);
    }
  }

  void _clearModeError() {
    final dismiss = _dismissModeError;
    _dismissModeError = null;
    dismiss?.call();
  }

  void _showModeError(bool entering) {
    _clearModeError();
    final revision = _modeRevision;
    final messenger = ScaffoldMessenger.of(context);
    var visible = false;
    var closed = false;
    var retired = false;
    var closeScheduled = false;
    late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> notice;
    void dismiss() {
      retired = true;
      if (!visible || closed || closeScheduled) return;
      closeScheduled = true;
      // Like app messages, close only our visible notice after closed futures
      // settle. A queued controller cannot close another notice ahead of it.
      Timer.run(() {
        if (messenger.mounted && !closed) notice.close();
      });
    }

    _dismissModeError = dismiss;
    notice = messenger.showSnackBar(
      SnackBar(
        content: Text(
          entering
              ? 'Could not enter full screen. Please try again.'
              : 'Could not restore the system controls. Please try again.',
        ),
        onVisible: () {
          visible = true;
          if (retired || !mounted || revision != _modeRevision) dismiss();
        },
        action: entering
            ? null
            : SnackBarAction(
                label: 'Retry',
                onPressed: () {
                  if (!mounted || revision != _modeRevision || _fullscreen) {
                    return;
                  }
                  _requestImmersiveMode(false);
                },
              ),
      ),
    );
    unawaited(
      notice.closed.then((_) {
        closed = true;
      }),
    );
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = _keepControlsVisible || !_controlsVisible;
      _updateControlsTimer(restart: true);
    });
  }

  @override
  void dispose() {
    app.removeListener(_appChanged);
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    _hideControlsTimer?.cancel();
    _clearModeError();
    if (_platformMayBeFullscreen) _requestImmersiveMode(false);
    super.dispose();
  }

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
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final stage = _VideoStage(
      key: _stageKey,
      app: app,
      onLoad: onLoad,
      onDevices: onDevices,
      fullscreen: _fullscreen,
    );
    if (_fullscreen) return _buildFullscreen(stage);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Scaffold resizes above the keyboard. Keep the tablet chat mounted
            // so the focused composer and its draft survive that resize.
            final layoutHeight = constraints.maxHeight + keyboardInset;
            final tablet = constraints.maxWidth >= 700 && layoutHeight >= 500;
            final twoColumn =
                constraints.maxWidth >= 900 && layoutHeight >= 500;
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
                              ? app.target.snapshot.media?.title ??
                                    'Your own screening'
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
                  if (_canEnterFullscreen)
                    IconButton(
                      onPressed: _enterFullscreen,
                      icon: const Icon(Icons.fullscreen_rounded),
                      tooltip: 'Enter full screen',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
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
                              onUpgrade: onUpgrade,
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
                  child: LayoutBuilder(
                    builder: (context, listConstraints) {
                      // The list clips a taller stage before its bottom reaction.
                      final stageHeight = tablet
                          ? math.min(
                              (listConstraints.maxWidth - 56) * 10 / 16,
                              math.max(0.0, listConstraints.maxHeight - 12),
                            )
                          : null;
                      return ListView(
                        padding: EdgeInsets.symmetric(
                          horizontal: tablet ? 28 : 20,
                        ),
                        children: [
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: stageHeight == null
                                ? AspectRatio(
                                    aspectRatio: 16 / 10,
                                    child: stage,
                                  )
                                : SizedBox(height: stageHeight, child: stage),
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
                      );
                    },
                  ),
                ),
                controls,
                _Actions(
                  app: app,
                  onLoad: onLoad,
                  onStartRoom: onStartRoom,
                  onUpgrade: onUpgrade,
                ),
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

  Widget _buildFullscreen(Widget stage) => Scaffold(
    backgroundColor: Colors.black,
    body: Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          exitFullscreen();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        key: const ValueKey('fullscreen-player'),
        children: [
          Positioned.fill(
            child: Semantics(
              label: 'Video',
              button: !_keepControlsVisible,
              onTap: _keepControlsVisible ? null : _toggleControls,
              child: GestureDetector(
                key: const ValueKey('fullscreen-video-surface'),
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: _toggleControls,
                child: stage,
              ),
            ),
          ),
          if (_controlsVisible)
            Positioned.fill(
              child: SafeArea(
                minimum: const EdgeInsets.all(8),
                child: LayoutBuilder(
                  builder: (context, constraints) => Focus(
                    onFocusChange: (focused) {
                      if (!mounted) return;
                      setState(() {
                        _controlsFocused = focused;
                        _updateControlsTimer();
                      });
                    },
                    child: Listener(
                      behavior: HitTestBehavior.deferToChild,
                      onPointerDown: (_) {
                        _controlsPressed = true;
                        _updateControlsTimer();
                      },
                      onPointerUp: (_) {
                        _controlsPressed = false;
                        _updateControlsTimer(restart: true);
                      },
                      onPointerCancel: (_) {
                        _controlsPressed = false;
                        _updateControlsTimer(restart: true);
                      },
                      child: Stack(
                        children: [
                          Align(
                            alignment: Alignment.topCenter,
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: .76),
                              child: Row(
                                children: [
                                  _fullscreenButton(
                                    tooltip: 'Exit full screen',
                                    icon: Icons.fullscreen_exit_rounded,
                                    onPressed: exitFullscreen,
                                  ),
                                  Expanded(
                                    child: Text(
                                      app.target.snapshot.media?.title ??
                                          'Your video',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(color: Colors.white),
                                    ),
                                  ),
                                  _fullscreenButton(
                                    tooltip: 'Choose video',
                                    icon: Icons.video_library_outlined,
                                    onPressed: onLoad,
                                  ),
                                  _fullscreenButton(
                                    tooltip: 'Choose playback screen',
                                    icon: Icons.devices_rounded,
                                    onPressed: onDevices,
                                  ),
                                  if (!app.isLocal)
                                    _fullscreenButton(
                                      tooltip: 'Room chat',
                                      icon: Icons.chat_bubble_outline_rounded,
                                      onPressed: () =>
                                          showChatSheet(context, app),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: constraints.maxHeight * .6,
                              ),
                              child: ColoredBox(
                                color: Colors.black.withValues(alpha: .76),
                                child: SingleChildScrollView(
                                  child: _PlaybackControls(
                                    app: app,
                                    onToggle: onTogglePlay,
                                    onSeek: onSeek,
                                    compact: true,
                                  ),
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
            ),
        ],
      ),
    ),
  );

  Widget _fullscreenButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) => IconButton(
    tooltip: tooltip,
    icon: Icon(icon),
    color: Colors.white,
    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    onPressed: onPressed,
  );
}

class _VideoStage extends StatelessWidget {
  const _VideoStage({
    super.key,
    required this.app,
    required this.onLoad,
    required this.onDevices,
    this.fullscreen = false,
  });
  final AppController app;
  final VoidCallback onLoad, onDevices;
  final bool fullscreen;
  @override
  Widget build(BuildContext context) {
    final target = app.target;
    final state = target.snapshot;
    final controller = target is LocalMobileTarget ? target.controller : null;
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 24;
    return LayoutBuilder(
      builder: (context, stageConstraints) => ColoredBox(
        color: fullscreen ? Colors.black : const Color(0xFF070B12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (app.isRestoringHistory ||
                state.connection == PlaybackConnection.loading)
              SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      app.isRestoringHistory
                          ? 'Restoring your video…'
                          : 'Opening your video…',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else if (controller != null && state.ready)
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
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
              Padding(
                padding: fullscreen
                    ? const EdgeInsets.only(top: 64, bottom: 112)
                    : EdgeInsets.zero,
                child: SingleChildScrollView(
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
                          child: Text(
                            state.error!,
                            textAlign: TextAlign.center,
                          ),
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
              ),
            if (!app.isRestoringHistory &&
                state.buffering &&
                state.ready &&
                app.playRequested)
              const CircularProgressIndicator(),
            if (app.reaction != null)
              Positioned(
                right: 24,
                bottom: math.min(20.0, stageConstraints.maxHeight * .1),
                child: Semantics(
                  key: const ValueKey('active-room-reaction'),
                  label:
                      '${app.reaction!.username} reacted ${app.reaction!.emoji}',
                  excludeSemantics: true,
                  child: SizedBox.square(
                    dimension: math.min(
                      80.0,
                      math.max(
                        0.0,
                        stageConstraints.maxHeight -
                            math.min(20.0, stageConstraints.maxHeight * .1),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        app.reaction!.emoji,
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(fontSize: 60),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
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
    final playRequested = widget.app.playRequested;
    final ready =
        !widget.app.isRestoringHistory &&
        state.ready &&
        (widget.app.isLocal || widget.app.isConnected);
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
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: ready ? widget.onToggle : null,
                  icon: Icon(
                    playRequested
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  tooltip: playRequested ? 'Pause together' : 'Play together',
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
                      playRequested
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    tooltip: playRequested ? 'Pause' : 'Play',
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
    this.onUpgrade,
  });
  final AppController app;
  final VoidCallback onLoad, onStartRoom;
  final VoidCallback? onUpgrade;
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
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: app.billing,
      builder: (context, _) => Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.sizeOf(context).height * .8,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Send a reaction',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text('A little feeling, shared together.'),
                const SizedBox(height: 20),
                _reactionChoices(context, standardReactions),
                const SizedBox(height: 20),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Movie night · Plus',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          app.billing.isPlus
                              ? 'For the scenes worth reacting to.'
                              : 'Six more ways to share the moment with Plus.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 12),
                        _reactionChoices(context, movieNightReactions),
                        if (!app.billing.isPlus) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: onUpgrade == null
                                ? null
                                : () => _upgrade(context),
                            icon: const Icon(Icons.lock_outline_rounded),
                            label: const Text('Unlock with Plus'),
                          ),
                        ],
                      ],
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

  Widget _reactionChoices(BuildContext context, List<String> choices) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final emoji in choices)
        Semantics(
          label: isPremiumReaction(emoji) && !app.billing.isPlus
              ? 'React $emoji, requires Plus'
              : 'React $emoji',
          button: true,
          child: TextButton(
            key: ValueKey('reaction-$emoji'),
            onPressed:
                isPremiumReaction(emoji) &&
                    !app.billing.isPlus &&
                    onUpgrade == null
                ? null
                : () {
                    if (isPremiumReaction(emoji) && !app.billing.isPlus) {
                      _upgrade(context);
                      return;
                    }
                    app.sendReaction(emoji);
                    HapticFeedback.selectionClick();
                    Navigator.pop(context);
                  },
            child: Text(emoji, style: const TextStyle(fontSize: 32)),
          ),
        ),
    ],
  );

  void _upgrade(BuildContext context) {
    final upgrade = onUpgrade;
    if (upgrade == null) return;
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => upgrade());
  }
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
          foregroundColor: Theme.of(context).colorScheme.onSurface,
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
