import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:nearby_platform/nearby_platform.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/app_controller.dart';
import '../../core/nearby/android_lan.dart';
import '../../core/nearby/nearby_desktop_target.dart';
import 'pairing_scanner.dart';

typedef NearbyInvitationScanner =
    Future<String?> Function(BuildContext context);

abstract interface class NearbyDevicesBackend {
  Stream<NearbyDiscoveryEvent> get discoveries;
  Future<List<NearbyClientCredential>> loadSaved();
  Future<void> startDiscovery();
  Future<void> stopDiscovery();
  Future<NearbyDesktopTarget> connect(
    NearbyClientCredential credential, {
    NearbyAdvertisement? advertisement,
  });
  Future<NearbyDesktopTarget> pair(
    PairingInvitation invitation, {
    required String clientName,
    required ValueChanged<NearbyClientState> onState,
  });
  Future<void> cancelPairing();
  Future<void> remove(String desktopId);
  Future<void> dispose();
}

Future<void> showNearbyDevicesSheet(
  BuildContext context, {
  required AppController app,
  NearbyDevicesBackend? backend,
  NearbyInvitationScanner scanner = scanNearbyInvitation,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 720),
  builder: (context) => FractionallySizedBox(
    heightFactor: .86,
    child: NearbyDevicesSheet(app: app, backend: backend, scanner: scanner),
  ),
);

class NearbyDevicesSheet extends StatefulWidget {
  const NearbyDevicesSheet({
    super.key,
    required this.app,
    this.backend,
    this.scanner = scanNearbyInvitation,
  });

  final AppController app;
  final NearbyDevicesBackend? backend;
  final NearbyInvitationScanner scanner;

  @override
  State<NearbyDevicesSheet> createState() => _NearbyDevicesSheetState();
}

class _NearbyDevicesSheetState extends State<NearbyDevicesSheet> {
  NearbyDevicesBackend? _backend;
  StreamSubscription<NearbyDiscoveryEvent>? _discoveries;
  final Map<String, NearbyAdvertisement> _advertisements = {};
  List<NearbyClientCredential> _saved = const [];
  NearbyClientState? _pairingState;
  String? _error;
  String? _discoveryWarning;
  bool _loading = true;
  bool _working = false;
  bool _cancelling = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final backend = widget.backend ?? await _PlatformNearbyBackend.create();
      if (_disposed) {
        await backend.dispose();
        return;
      }
      _backend = backend;
      _discoveries = backend.discoveries.listen(_discovered);
      _saved = await backend.loadSaved();
      if (!mounted) return;
      setState(() => _loading = false);
      try {
        await backend.startDiscovery();
      } catch (error) {
        if (mounted) {
          setState(() => _discoveryWarning = _messageFor(error));
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _messageFor(error);
        });
      }
    }
  }

  void _discovered(NearbyDiscoveryEvent event) {
    if (!mounted) return;
    setState(() {
      if (event.status == NearbyMdnsStatus.lost) {
        _advertisements.remove(event.advertisement.desktopId);
      } else {
        _advertisements[event.advertisement.desktopId] = event.advertisement;
      }
    });
  }

  Future<void> _refreshSaved() async {
    final backend = _backend;
    if (backend == null) return;
    try {
      final saved = await backend.loadSaved();
      if (mounted) setState(() => _saved = saved);
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    }
  }

  Future<void> _scan() async {
    if (_working) return;
    final payload = await widget.scanner(context);
    if (payload != null && mounted) await _pairPayload(payload);
  }

  Future<void> _paste() async {
    if (_working) return;
    var entered = '';
    final payload = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste pairing invitation'),
        content: TextField(
          key: const Key('nearby-invitation-field'),
          autofocus: true,
          maxLength: 2048,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'Paste the full invitation from MeowWatch desktop',
          ),
          onChanged: (value) => entered = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, entered),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (payload != null && mounted) await _pairPayload(payload);
  }

  Future<void> _pairPayload(String payload) async {
    PairingInvitation invitation;
    try {
      invitation = PairingInvitation.decodeQr(payload.trim());
    } catch (_) {
      setState(() {
        _error =
            'That invitation is not valid. Copy a fresh pairing invitation from your desktop.';
      });
      return;
    }
    final backend = _backend;
    if (backend == null) return;
    setState(() {
      _working = true;
      _cancelling = false;
      _error = null;
      _pairingState = const NearbyClientState(NearbyClientPhase.connecting);
    });
    try {
      final target = await backend.pair(
        invitation,
        clientName: widget.app.username,
        onState: (state) {
          if (mounted) setState(() => _pairingState = state);
        },
      );
      if (!mounted) {
        await target.close();
        return;
      }
      if (await widget.app.adoptNearby(target) && mounted) {
        Navigator.pop(context);
      } else {
        setState(() => _error = 'Could not switch to that desktop. Try again.');
      }
    } catch (error) {
      if (mounted && !_cancelling) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _cancelling = false;
          _pairingState = null;
        });
        await _refreshSaved();
      }
    }
  }

  Future<void> _connect(NearbyClientCredential credential) async {
    final backend = _backend;
    if (backend == null || _working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final target = await backend.connect(
        credential,
        advertisement: _advertisements[credential.desktopId],
      );
      if (!mounted) {
        await target.close();
        return;
      }
      if (await widget.app.adoptNearby(target) && mounted) {
        Navigator.pop(context);
      } else {
        setState(() => _error = 'Could not switch to that desktop. Try again.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _cancelPairing() async {
    if (!_working || _cancelling) return;
    setState(() => _cancelling = true);
    await _backend?.cancelPairing();
  }

  Future<void> _watchOnPhone() async {
    if (_working || !widget.app.isNearby) return;
    setState(() => _working = true);
    try {
      if (await widget.app.watchOnPhone() && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _remove(NearbyClientCredential credential) async {
    if (_working) return;
    final connected =
        widget.app.nearby?.credential.desktopId == credential.desktopId &&
        widget.app.nearby!.connected;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          connected ? 'Revoke this phone?' : 'Remove from this phone?',
        ),
        content: Text(
          connected
              ? 'The desktop will revoke this phone, then this saved pairing will be removed here.'
              : 'This removes the saved pairing only from this phone. Remove the phone on the desktop separately if it is still listed there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(connected ? 'Revoke' : 'Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      if (connected) {
        await widget.app.nearby!.client.command('device.revokeSelf');
        await widget.app.watchOnPhone();
      }
      await _backend!.remove(credential.desktopId);
      await _refreshSaved();
    } catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_discoveries?.cancel());
    unawaited(_backend?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final savedIds = _saved.map((item) => item.desktopId).toSet();
    final unpaired = _advertisements.values
        .where((item) => !savedIds.contains(item.desktopId))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Playback screen',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                onPressed: _working ? null : () => Navigator.pop(context),
                tooltip: 'Close device chooser',
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Loading nearby devices',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  children: [
                    if (_error != null)
                      _Notice(
                        icon: Icons.error_outline_rounded,
                        text: _error!,
                        color: colors.error,
                      ),
                    if (_discoveryWarning != null)
                      _Notice(
                        icon: Icons.wifi_off_rounded,
                        text:
                            '${_discoveryWarning!} Saved pairings and invitations still work.',
                        color: colors.onSurfaceVariant,
                      ),
                    ListTile(
                      minVerticalPadding: 12,
                      leading: const Icon(Icons.smartphone_rounded),
                      title: const Text('This phone'),
                      subtitle: const Text('Play video and room audio here'),
                      trailing: widget.app.isNearby
                          ? const Icon(Icons.chevron_right_rounded)
                          : const Icon(Icons.check_circle_rounded),
                      enabled: !_working,
                      onTap: widget.app.isNearby ? _watchOnPhone : null,
                    ),
                    if (widget.app.isNearby)
                      ListTile(
                        minVerticalPadding: 12,
                        leading: const Icon(Icons.desktop_windows_rounded),
                        title: Text(widget.app.nearby!.label),
                        subtitle: const Text(
                          'Connected and verified · controlling desktop playback',
                        ),
                        trailing: const Icon(Icons.check_circle_rounded),
                      ),
                    if (_saved.isNotEmpty) ...[
                      const _SectionLabel('Paired desktops'),
                      ..._saved.map((credential) {
                        final advertisement =
                            _advertisements[credential.desktopId];
                        return ListTile(
                          minVerticalPadding: 12,
                          leading: const Icon(Icons.desktop_windows_outlined),
                          title: Text(
                            advertisement?.displayName ?? 'Paired desktop',
                          ),
                          subtitle: Text(
                            advertisement == null
                                ? 'Saved pairing · connect using its verified address'
                                : 'Found nearby · saved pairing verified on connect',
                          ),
                          enabled: !_working,
                          onTap: () => _connect(credential),
                          trailing: IconButton(
                            tooltip: 'Remove saved pairing',
                            onPressed: _working
                                ? null
                                : () => _remove(credential),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        );
                      }),
                    ],
                    if (unpaired.isNotEmpty) ...[
                      const _SectionLabel('Found nearby'),
                      ...unpaired.map(
                        (device) => ListTile(
                          minVerticalPadding: 12,
                          leading: const Icon(Icons.desktop_windows_outlined),
                          title: Text(device.displayName),
                          subtitle: Text(
                            device.pairingOpen
                                ? 'Pairing is open · scan or paste its invitation'
                                : 'Open Pair a phone on this desktop',
                          ),
                        ),
                      ),
                    ],
                    if (_saved.isEmpty && unpaired.isEmpty && _error == null)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 28, 20, 20),
                        child: Column(
                          children: [
                            Icon(
                              Icons.desktop_access_disabled_outlined,
                              size: 38,
                            ),
                            SizedBox(height: 14),
                            Text(
                              'No desktop is visible yet. Open Nearby devices in MeowWatch desktop, or use its pairing invitation.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    if (_working && _pairingState != null)
                      _PairingProgress(
                        state: _pairingState!,
                        cancelling: _cancelling,
                        onCancel: _cancelPairing,
                      ),
                    const SizedBox(height: 18),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          key: const Key('scan-nearby-button'),
                          onPressed: _working ? null : _scan,
                          icon: const Icon(Icons.qr_code_scanner_rounded),
                          label: const Text('Scan pairing code'),
                        ),
                        OutlinedButton.icon(
                          key: const Key('paste-nearby-button'),
                          onPressed: _working ? null : _paste,
                          icon: const Icon(Icons.content_paste_rounded),
                          label: const Text('Paste invitation'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your desktop must approve every new phone. Pairing details stay in protected device storage.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: color)),
          ),
        ],
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _PairingProgress extends StatelessWidget {
  const _PairingProgress({
    required this.state,
    required this.cancelling,
    required this.onCancel,
  });
  final NearbyClientState state;
  final bool cancelling;
  final VoidCallback onCancel;
  @override
  Widget build(BuildContext context) {
    final text = switch (state.phase) {
      NearbyClientPhase.awaitingApproval =>
        'Approve this phone on your desktop to finish pairing.',
      NearbyClientPhase.saving => 'Saving this pairing securely…',
      NearbyClientPhase.authenticating => 'Verifying the saved desktop…',
      NearbyClientPhase.pairing => 'Verifying the pairing invitation…',
      _ => 'Connecting on your local network…',
    };
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            TextButton(
              onPressed: cancelling ? null : onCancel,
              child: Text(cancelling ? 'Cancelling…' : 'Cancel pairing'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformNearbyBackend implements NearbyDevicesBackend {
  _PlatformNearbyBackend({
    required this.store,
    required this.lan,
    required this.discovery,
  });

  final ProtectedNearbyStore store;
  final AndroidLan lan;
  final NearbyDiscovery discovery;
  NearbyClient? _pairingClient;
  bool _disposed = false;

  static Future<_PlatformNearbyBackend> create() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final resolved = await directory.resolveSymbolicLinks();
    final namespaceHash = sha256.convert(utf8.encode(resolved)).toString();
    return _PlatformNearbyBackend(
      store: ProtectedNearbyStore(namespaceHash: namespaceHash),
      lan: AndroidLan(),
      discovery: NearbyDiscovery(),
    );
  }

  @override
  Stream<NearbyDiscoveryEvent> get discoveries => discovery.events;

  @override
  Future<List<NearbyClientCredential>> loadSaved() =>
      store.listClientCredentials();

  @override
  Future<void> startDiscovery() async {
    if ((await lan.list()).isEmpty) {
      throw const NearbyException('lan_unavailable');
    }
    await discovery.start();
  }

  @override
  Future<void> stopDiscovery() => discovery.stop();

  @override
  Future<NearbyDesktopTarget> connect(
    NearbyClientCredential credential, {
    NearbyAdvertisement? advertisement,
  }) async {
    final endpoint = await _validatedEndpoint(credential, advertisement);
    final route = await lan.routeFor(endpoint);
    final target = NearbyDesktopTarget(
      client: NearbyClient(store: store.clientStore),
      credential: credential,
    );
    try {
      await target.connect(route.subnet, endpoint: endpoint);
      return target;
    } catch (_) {
      await target.close();
      rethrow;
    }
  }

  Future<LanEndpoint> _validatedEndpoint(
    NearbyClientCredential credential,
    NearbyAdvertisement? advertisement,
  ) async {
    if (advertisement?.desktopId == credential.desktopId) {
      for (final hint in advertisement!.addressHints) {
        try {
          final endpoint = LanEndpoint(
            address: LanIpv4Address.parse(hint),
            port: advertisement.port,
          );
          await lan.routeFor(endpoint);
          return endpoint;
        } catch (_) {
          // Discovery hints are untrusted. Ignore anything off-link or malformed.
        }
      }
    }
    await lan.routeFor(credential.endpoint);
    return credential.endpoint;
  }

  @override
  Future<NearbyDesktopTarget> pair(
    PairingInvitation invitation, {
    required String clientName,
    required ValueChanged<NearbyClientState> onState,
  }) async {
    final route = await lan.routeFor(invitation.endpoint);
    final pairingClient = NearbyClient(store: store.clientStore);
    _pairingClient = pairingClient;
    final states = pairingClient.states.listen(onState);
    NearbyClientCredential credential;
    try {
      credential = await pairingClient.pair(
        invitation: invitation,
        subnet: route.subnet,
        clientName: clientName,
      );
    } finally {
      await states.cancel();
      if (identical(_pairingClient, pairingClient)) _pairingClient = null;
      await pairingClient.dispose();
    }
    if (_disposed) throw const NearbyException('cancelled');
    return connect(credential);
  }

  @override
  Future<void> cancelPairing() async {
    final pairing = _pairingClient;
    _pairingClient = null;
    await pairing?.dispose();
  }

  @override
  Future<void> remove(String desktopId) => store.clientStore.remove(desktopId);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancelPairing();
    await discovery.dispose();
  }
}

String _messageFor(Object error) {
  final code = switch (error) {
    NearbyException value => value.code,
    NearbyPlatformException value => value.code,
    NearbyStorageException value => value.code,
    PlatformException value => value.code,
    _ => 'not_connected',
  };
  return nearbyErrorMessage(code);
}
