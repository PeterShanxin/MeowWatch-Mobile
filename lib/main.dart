import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_controller.dart';
import 'app/app_services.dart';
import 'ui/app_theme.dart';
import 'ui/home/home_screen.dart';
import 'ui/home/onboarding_screen.dart';
import 'ui/join/join_sheet.dart';
import 'ui/media/media_sheet.dart';
import 'ui/paywall/paywall_sheet.dart';
import 'ui/room/invite_sheet.dart';
import 'ui/room/room_screen.dart';
import 'ui/settings/settings_sheet.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF10141F),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key, this.controller});
  final AppController? controller;
  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _navigator = GlobalKey<NavigatorState>();
  AppController? _app;
  Object? _loadError;
  bool _paywallOpen = false;
  String? _lastMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
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
      setState(() => _loadError = null);
      if (widget.controller == null) unawaited(app.billing.configure());
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _app == null) return;
      final app = _app!;
      if (app.message != null && app.message != _lastMessage) {
        _lastMessage = app.message;
        _messenger.currentState?.showSnackBar(
          SnackBar(
            content: Text(app.message!),
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: app.dismissMessage,
            ),
          ),
        );
      }
      if (app.message == null) _lastMessage = null;
      if (app.needsPlus && !_paywallOpen) {
        unawaited(_upgrade(retryIntent: true));
      }
    });
  }

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
  Future<void> _join() async {
    final context = _context;
    if (context == null) return;
    final value = await showJoinSheet(context, app: _app!);
    if (value != null && mounted) {
      await _run(() async {
        await _app!.joinRoom(value);
      });
    }
  }

  Future<void> _load() async {
    final context = _context;
    if (context == null) return;
    final media = await showMediaSheet(context, app: _app!);
    if (media != null && mounted) await _run(() => _app!.load(media));
  }

  Future<void> _upgrade({bool retryIntent = false}) async {
    final context = _context;
    if (_paywallOpen || context == null || _app == null) return;
    _paywallOpen = true;
    _app!.dismissPaywall();
    try {
      final unlocked = await showPaywallSheet(context, app: _app!);
      if (unlocked == true && retryIntent && mounted) {
        if (_app!.room == null) {
          await _start();
        } else if (!_app!.target.snapshot.playing) {
          await _run(_app!.togglePlay);
        }
      }
    } finally {
      _paywallOpen = false;
    }
  }

  Future<void> _settings() async {
    final context = _context;
    if (context != null) {
      await showSettingsSheet(context, app: _app!, onUpgrade: () => _upgrade());
    }
  }

  Future<void> _devices() async {
    final context = _context;
    if (context == null) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Playback screen',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.smartphone_rounded),
              title: const Text('This phone'),
              subtitle: const Text('Video and room controls on this device'),
              trailing: const Icon(Icons.check_circle_outline),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final app = _app;
    if (app == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_run(app.background));
    } else if (state == AppLifecycleState.resumed &&
        app.billing.isConfigured &&
        !app.billing.isBusy) {
      unawaited(app.billing.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      theme: meowWatchTheme(),
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
                      onLoad: _load,
                      onInvite: () {
                        if (_context != null) showInviteSheet(_context!, app);
                      },
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
                                  const Text(
                                    'Finding your room…',
                                    style: TextStyle(fontSize: 22),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Establishing a secure connection.',
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
