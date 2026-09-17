import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';

import 'app/app_controller.dart';
import 'app/app_services.dart';
import 'app/incoming_links.dart';
import 'app/incoming_media.dart';
import 'core/cast/cast_playback_target.dart';
import 'core/connect/room_config.dart';
import 'core/session/room_invite.dart';
import 'data/app_repository.dart';
import 'ui/app_theme.dart';
import 'ui/devices/playback_devices_sheet.dart';
import 'ui/home/home_screen.dart';
import 'ui/home/onboarding_screen.dart';
import 'ui/join/join_sheet.dart';
import 'ui/media/media_sheet.dart';
import 'ui/nearby/nearby_devices_sheet.dart';
import 'ui/paywall/paywall_sheet.dart';
import 'ui/room/invite_sheet.dart';
import 'ui/room/room_screen.dart';
import 'ui/settings/about_sheet.dart';
import 'ui/settings/settings_sheet.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerMeowWatchLicenses();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF10141F),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(
    MainApp(
      incomingLinkSource: AppLinksIncomingLinkSource(),
      incomingMediaSource: defaultTargetPlatform == TargetPlatform.android
          ? AndroidIncomingMediaSource()
          : null,
    ),
  );
}

class MainApp extends StatefulWidget {
  const MainApp({
    super.key,
    this.controller,
    this.incomingLinkSource,
    this.incomingMediaSource,
  });
  final AppController? controller;
  final IncomingLinkSource? incomingLinkSource;
  final IncomingMediaSource? incomingMediaSource;
  @override
  State<MainApp> createState() => _MainAppState();
}

class _AppMessageSnackBar {
  _AppMessageSnackBar(this.version);

  final int version;
  late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
  controller;
  bool visible = false;
  bool closed = false;
  bool retired = false;
  bool closeScheduled = false;
}

class _MainAppState extends State<MainApp> with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _navigator = GlobalKey<NavigatorState>();
  AppController? _app;
  Object? _loadError;
  bool _paywallOpen = false;
  bool _modalOpen = false;
  String? _lastMessage;
  int _messageVersion = 0;
  _AppMessageSnackBar? _appMessageSnackBar;
  IncomingLinks? _incomingLinks;
  IncomingMediaInbox? _incomingMedia;
  final List<IncomingMedia> _pendingIncomingMedia = [];
  final List<Uri> _pendingIncomingInvites = [];
  String? _activeIncomingInvite;
  String? _incomingError;
  bool _incomingFlowOpen = false;
  bool _incomingDrainScheduled = false;
  WatchHistoryEntry? _pendingWatchAgain;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final source = widget.incomingLinkSource;
    if (source != null) {
      _incomingLinks = IncomingLinks(source);
      unawaited(
        _incomingLinks!.start(
          onLink: _receiveIncomingLink,
          onError: (_) => _queueIncomingError(
            'Could not read that room invitation. Open it again and retry.',
          ),
        ),
      );
    }
    final mediaSource = widget.incomingMediaSource;
    if (mediaSource != null) {
      _incomingMedia = IncomingMediaInbox(mediaSource);
      unawaited(
        _incomingMedia!.start(
          onMedia: _receiveIncomingMedia,
          onError: (_) => _queueIncomingError(
            'Could not receive that video. Try sharing it again.',
          ),
        ),
      );
    }
    unawaited(_open());
  }

  void _receiveIncomingMedia(IncomingMedia incoming) {
    if (!mounted) return;
    if (incoming.invite != null) {
      _receiveIncomingLink(incoming.invite!);
      return;
    }
    if (incoming.error != null) {
      _queueIncomingError(incoming.error!);
      return;
    }
    if (incoming.media == null) return;
    if (_pendingIncomingMedia.length >= 4) {
      _queueIncomingError(
        'Several videos arrived at once. Finish the current video, then share the next one again.',
      );
      return;
    }
    _pendingIncomingMedia.add(incoming);
    _scheduleIncomingDrain();
  }

  Future<void> _open() async {
    try {
      final app = widget.controller ?? await openAppServices();
      if (!mounted) {
        if (widget.controller == null) await app.close();
        return;
      }
      _app = app;
      app.addListener(_changed);
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle == AppLifecycleState.paused ||
          lifecycle == AppLifecycleState.hidden) {
        unawaited(_run(app.background));
      }
      setState(() => _loadError = null);
      _scheduleIncomingDrain();
      if (widget.controller == null) unawaited(app.billing.configure());
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  void _changed() {
    if (!mounted) return;
    if (_app?.message != _lastMessage) {
      _lastMessage = _app?.message;
      _messageVersion++;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _app == null) return;
      final app = _app!;
      _syncMessageSnackBar(app);
      if (app.needsPlus && !_paywallOpen) {
        unawaited(_upgrade(retryIntent: true));
      }
      _scheduleIncomingDrain();
    });
  }

  void _syncMessageSnackBar(AppController app) {
    if (_appMessageSnackBar?.version == _messageVersion) return;
    final previous = _appMessageSnackBar;
    _appMessageSnackBar = null;
    if (previous != null) {
      previous.retired = true;
      _closeRetiredMessage(previous);
    }
    final message = app.message;
    final messenger = _messenger.currentState;
    if (message == null || messenger == null) return;
    final notice = _AppMessageSnackBar(_messageVersion);
    _appMessageSnackBar = notice;
    notice.controller = messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        onVisible: () {
          notice.visible = true;
          _closeRetiredMessage(notice);
        },
        action: SnackBarAction(
          label: 'Dismiss',
          onPressed: () {
            if (mounted &&
                identical(_appMessageSnackBar, notice) &&
                notice.version == _messageVersion &&
                app.message == message) {
              app.dismissMessage();
            }
          },
        ),
      ),
    );
    unawaited(
      notice.controller.closed.then((_) {
        notice.closed = true;
      }),
    );
  }

  void _closeRetiredMessage(_AppMessageSnackBar notice) {
    if (!notice.retired ||
        !notice.visible ||
        notice.closed ||
        notice.closeScheduled) {
      return;
    }
    notice.closeScheduled = true;
    // A queued controller cannot close itself. Once visible, let already-closed
    // futures settle before closing only our own front-of-queue notification.
    Timer.run(() {
      if (mounted && !notice.closed) notice.controller.close();
    });
  }

  void _receiveIncomingLink(Uri uri) {
    if (!mounted) return;
    // Media VIEW intents are handled by the Android share/open bridge.
    if (uri.scheme != 'meowwatch') return;
    try {
      if (uri.scheme != 'meowwatch' || uri.host != 'join') {
        throw const FormatException('This is not a room invitation.');
      }
      parseRoomInvite(uri.toString(), _app?.username ?? 'Guest');
    } on FormatException catch (error) {
      _queueIncomingError(
        'Could not open that room invitation. ${error.message}',
      );
      return;
    }

    final value = uri.toString();
    if (_pendingIncomingInvites.any((pending) => pending.toString() == value) ||
        _activeIncomingInvite == value) {
      return;
    }
    if (_pendingIncomingInvites.length >= 4) {
      _incomingError ??=
          'Several room invitations arrived at once. Finish the current invitation, then open the one you want again.';
    } else {
      _pendingIncomingInvites.add(uri);
    }
    _scheduleIncomingDrain();
  }

  void _queueIncomingError(String message) {
    if (!mounted) return;
    _incomingError = message;
    _scheduleIncomingDrain();
  }

  void _scheduleIncomingDrain() {
    if (!mounted || _incomingDrainScheduled) return;
    _incomingDrainScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _incomingDrainScheduled = false;
      if (mounted) unawaited(_drainIncoming());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _drainIncoming() async {
    if (!mounted) return;
    final error = _incomingError;
    final messenger = _messenger.currentState;
    if (error != null && messenger != null) {
      _incomingError = null;
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }

    final app = _app;
    final context = _context;
    final pending = _pendingIncomingInvites.firstOrNull;
    final pendingMedia = _pendingIncomingMedia.firstOrNull;
    if (_incomingFlowOpen ||
        (pending == null && pendingMedia == null) ||
        app == null ||
        context == null ||
        app.firstLaunch ||
        app.busy ||
        _paywallOpen ||
        _modalOpen) {
      return;
    }

    if (pending != null) {
      _pendingIncomingInvites.removeAt(0);
      _activeIncomingInvite = pending.toString();
    } else {
      _pendingIncomingMedia.removeAt(0);
    }
    _incomingFlowOpen = true;
    try {
      if (pending != null) {
        await _reviewIncomingInvite(context, app, pending);
      } else {
        await _reviewIncomingMedia(context, app, pendingMedia!);
      }
    } finally {
      _incomingFlowOpen = false;
      _activeIncomingInvite = null;
      _scheduleIncomingDrain();
    }
  }

  Future<void> _reviewIncomingMedia(
    BuildContext context,
    AppController app,
    IncomingMedia incoming,
  ) async {
    final media = incoming.media!;
    final remote = app.isCasting || app.isNearby;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Open shared video?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(media.title, maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              Text(
                remote
                    ? 'Return to this phone to open the video. Your current video will be replaced.'
                    : app.room != null
                    ? 'Replace your video in the current room. Your companions need to open the same video.'
                    : 'Open this video on your phone, ready to play.',
              ),
              if (media.isNetwork) ...[
                const SizedBox(height: 12),
                Text(
                  'Video from ${media.uri.host}. Opening it connects to that server.',
                ),
              ],
              if (incoming.warning != null) ...[
                const SizedBox(height: 12),
                Text(incoming.warning!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-shared-video-button'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(remote ? 'Return & open' : 'Open video'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await _run(() async {
      if (app.isCasting) await app.returnFromCast();
      if (app.isNearby) await app.watchOnPhone();
      if (app.isCasting || app.isNearby || app.busy || !mounted) return;
      if (!app.inPlayer) await app.useLocalMode();
      await app.load(media);
    });
  }

  Future<void> _reviewIncomingInvite(
    BuildContext context,
    AppController app,
    Uri invite,
  ) async {
    if (!mounted) return;
    final config = parseRoomInvite(invite.toString(), app.username);
    final current = app.room?.config;
    if (_sameRoom(current, config)) {
      _messenger.currentState?.showSnackBar(
        const SnackBar(content: Text('You’re already in this room.')),
      );
      return;
    }

    if (current != null) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Leave current room?'),
          content: Text(
            'You received an invitation for “${config.room}”. Leave your current room and stop its playback before reviewing the invitation.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Stay in current room'),
            ),
            FilledButton(
              key: const Key('leave-and-review-invite-button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Leave & review invite'),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
      await _run(app.leavePlayer);
      if (!mounted || app.room != null || app.busy) return;
    }

    final reviewContext = _context;
    if (reviewContext == null || !reviewContext.mounted) return;
    final value = await showJoinSheet(
      reviewContext,
      app: app,
      initialInvite: invite.toString(),
    );
    if (value != null && mounted) {
      await _run(() async {
        await app.joinRoom(value);
      });
    }
  }

  static bool _sameRoom(RoomConfig? left, RoomConfig right) =>
      left != null &&
      left.server.toLowerCase() == right.server.toLowerCase() &&
      left.port == right.port &&
      left.room == right.room;

  Future<void> _run(Future<void> Function() operation) async {
    try {
      await operation();
    } on FormatException catch (error) {
      _app?.report(error.message);
    } catch (_) {
      _app?.report(
        'That did not finish. Check your connection and device storage, then try again.',
      );
    }
  }

  BuildContext? get _context => _navigator.currentContext;
  Future<void> _start() => _run(() async {
    await _app!.createRoom();
  });
  Future<void> _watchAgain(WatchHistoryEntry entry) => _run(() async {
    _pendingWatchAgain = entry;
    await _app!.watchAgain(entry);
    if (!_app!.needsPlus) _pendingWatchAgain = null;
  });
  Future<void> _join() async {
    final context = _context;
    if (context == null || _modalOpen) return;
    _modalOpen = true;
    try {
      final value = await showJoinSheet(context, app: _app!);
      if (value != null && mounted) {
        await _run(() async {
          await _app!.joinRoom(value);
        });
      }
    } finally {
      _modalOpen = false;
      _scheduleIncomingDrain();
    }
  }

  Future<void> _load() async {
    final context = _context;
    if (context == null || _modalOpen) return;
    _modalOpen = true;
    try {
      final media = await showMediaSheet(context, app: _app!);
      if (media != null && mounted) await _run(() => _app!.load(media));
    } finally {
      _modalOpen = false;
      _scheduleIncomingDrain();
    }
  }

  Future<void> _upgrade({bool retryIntent = false}) async {
    final context = _context;
    if (_paywallOpen || context == null || _app == null) return;
    _paywallOpen = true;
    _app!.dismissPaywall();
    try {
      final unlocked = await showPaywallSheet(context, app: _app!);
      if (unlocked == true && retryIntent && mounted) {
        final repeatedSession = _pendingWatchAgain;
        if (repeatedSession != null) {
          await _watchAgain(repeatedSession);
        } else if (_app!.room == null) {
          await _start();
        } else if (!_app!.target.snapshot.playing) {
          await _run(_app!.togglePlay);
        }
      }
    } finally {
      _pendingWatchAgain = null;
      _paywallOpen = false;
      _scheduleIncomingDrain();
    }
  }

  Future<void> _settings() async {
    final context = _context;
    if (context == null || _modalOpen) return;
    _modalOpen = true;
    try {
      await showSettingsSheet(context, app: _app!, onUpgrade: () => _upgrade());
    } finally {
      _modalOpen = false;
      _scheduleIncomingDrain();
    }
  }

  Future<void> _devices() async {
    final context = _context;
    if (context == null || _modalOpen) return;
    _modalOpen = true;
    try {
      final app = _app!;
      final choice = await showPlaybackDevicesSheet(context, app: app);
      if (!mounted) return;
      switch (choice) {
        case PlaybackDeviceChoice.phone:
          if (app.isCasting) await _run(app.returnFromCast);
          if (app.isNearby) {
            await _run(() async {
              await app.watchOnPhone();
            });
          }
        case PlaybackDeviceChoice.nearby:
          final deviceContext = _context;
          if (deviceContext != null && deviceContext.mounted) {
            await showNearbyDevicesSheet(deviceContext, app: app);
          }
        case PlaybackDeviceChoice.cast:
          await _run(() async {
            if (app.isCasting) {
              await app.cast!.showChooser();
            } else {
              await app.castTo(CastPlaybackTarget());
            }
          });
        case null:
          break;
      }
    } finally {
      _modalOpen = false;
      _scheduleIncomingDrain();
    }
  }

  Future<void> _invite() async {
    final context = _context;
    final app = _app;
    if (context == null || app == null || _modalOpen) return;
    _modalOpen = true;
    try {
      await showInviteSheet(context, app);
    } finally {
      _modalOpen = false;
      _scheduleIncomingDrain();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final app = _app;
    if (app == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_run(app.background));
    } else if (state == AppLifecycleState.resumed) {
      app.foreground();
      if (app.billing.isConfigured && !app.billing.isBusy) {
        unawaited(app.billing.refresh());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_incomingLinks?.dispose());
    unawaited(_incomingMedia?.dispose());
    _app?.removeListener(_changed);
    if (widget.controller == null) {
      unawaited(_app?.close().catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = _app;
    return MaterialApp(
      title: 'MeowWatch',
      debugShowCheckedModeBanner: false,
      theme: meowWatchTheme(theme: app?.theme ?? 'cozy'),
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
      home: app == null
          ? Scaffold(
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: _loadError == null
                        ? const CircularProgressIndicator(
                            semanticsLabel: 'Opening MeowWatch',
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.folder_off_outlined, size: 44),
                              const SizedBox(height: 20),
                              const Text(
                                'Could not read your saved sessions. Check available storage, then try again.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: () {
                                  setState(() => _loadError = null);
                                  unawaited(_open());
                                },
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            )
          : PopScope(
              canPop: !app.inPlayer && !app.busy,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) unawaited(_run(app.leavePlayer));
              },
              child: Stack(
                children: [
                  if (app.firstLaunch)
                    OnboardingScreen(
                      app: app,
                      onContinue: (name) => _run(() => app.setName(name)),
                    )
                  else if (app.inPlayer)
                    RoomScreen(
                      app: app,
                      onUpgrade: () => _upgrade(),
                      onLoad: _load,
                      onInvite: _invite,
                      onDevices: _devices,
                      onLeave: () => _run(app.leavePlayer),
                      onStartRoom: _start,
                      onTogglePlay: () => _run(app.togglePlay),
                      onSeek: (position) => _run(() => app.seek(position)),
                    )
                  else
                    HomeScreen(
                      app: app,
                      onJoin: _join,
                      onSettings: _settings,
                      onUpgrade: () => _upgrade(),
                      onStartRoom: _start,
                      onLocalMode: () => _run(app.useLocalMode),
                      onResume: (entry) => _run(() => app.resume(entry)),
                      onWatchAgain: _watchAgain,
                    ),
                  if (app.busy)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: .82),
                        child: SafeArea(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 24),
                                  Text(
                                    app.busyLabel,
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Getting everything ready.',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  TextButton(
                                    onPressed: () => _run(app.leavePlayer),
                                    child: const Text('Cancel'),
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
  }
}
