import '../connect/room_config.dart';
import 'endpoint_settings.dart';
import 'syncplay_client.dart';
import 'syncplay_endpoints.dart';

/// Shown when no public candidate completed a secure Hello. Deliberately does
/// not ask the user to name a server: the people who hit this are the ones with
/// no way to answer that question (#234).
const String kNoSyncplayServerMessage =
    'MeowWatch could not reach any Syncplay server right now. Check your '
    'internet connection and try again in a moment.';

/// What to do after one real join attempt during a public-candidate walk.
enum EndpointWalkDecision {
  /// Secure Hello completed and the room login succeeded. Stop and keep this
  /// client.
  success,

  /// No secure Hello. Tear this client down and try the next candidate.
  next,

  /// A public server completed Hello but refused this room. Stop walking —
  /// hopping would put the same room name on a different server.
  stop,
}

/// One step of [SyncplayEndpointDiscovery.walk].
typedef EndpointWalkAttempt =
    Future<EndpointWalkDecision> Function(SyncplayEndpoint endpoint);

/// A lobby or Continue Watching join that completed Hello.
class PublicEndpointJoin {
  const PublicEndpointJoin({
    required this.client,
    required this.endpoint,
    required this.config,
  });

  final SyncplayClient client;
  final SyncplayEndpoint endpoint;
  final RoomConfig config;
}

/// Result of [joinFirstWorkingEndpoint] or [joinPinnedEndpoint].
class SyncedJoinOutcome {
  const SyncedJoinOutcome.ok(this.join) : error = null, retainedClient = null;
  const SyncedJoinOutcome.fail(this.error, {this.retainedClient}) : join = null;

  final PublicEndpointJoin? join;
  final String? error;

  /// Client from an unsuccessful join. The caller must finish: pop the watch
  /// route if Hello already handed it to HomeScreen, or dispose it if not.
  final SyncplayClient? retainedClient;
}

/// Picks the public Syncplay endpoint a default session should use, and
/// remembers the one that worked.
///
/// Candidates are walked **sequentially, in the curated order**. Racing them
/// would be faster and wrong: the winner would be whichever answered first from
/// *this* machine, so two friends resolving independently could land on
/// different servers and each see an empty room. A fixed order means the same
/// starting point yields the same answer on both sides.
///
/// Each step is a real join ([SyncplayClient.connectUntilJoin]), not a
/// throwaway probe. The first secure Hello that logs into the user's room is
/// the session — that client is handed to HomeScreen. A failed candidate is
/// disposed before the next dial.
class SyncplayEndpointDiscovery {
  SyncplayEndpointDiscovery({
    required this.settings,
    this.candidates = kPublicSyncplayEndpoints,
    this.onLog,
  });

  final EndpointSettings settings;
  final List<SyncplayEndpoint> candidates;
  final void Function(String line)? onLog;

  /// Walks [candidates] (and [preferred], when it is one of them).
  ///
  /// [preferred] is the endpoint a room already lives on (a saved room, a
  /// resumed history entry). It is tried first. Endpoints outside [candidates]
  /// are never dialled here — a server the user named is the caller's to use
  /// as-is, not discovery's to second-guess.
  Future<SyncplayEndpoint?> walk({
    SyncplayEndpoint? preferred,
    required EndpointWalkAttempt attempt,
  }) async {
    for (final endpoint in await _searchOrder(preferred)) {
      switch (await attempt(endpoint)) {
        case EndpointWalkDecision.success:
          await rememberPublicSyncplayEndpoint(
            settings,
            endpoint,
            onLog: onLog,
          );
          return endpoint;
        case EndpointWalkDecision.stop:
          onLog?.call(
            'endpoint discovery: $endpoint completed Hello but refused the room',
          );
          return null;
        case EndpointWalkDecision.next:
          onLog?.call('endpoint discovery: $endpoint did not answer');
      }
    }
    onLog?.call('endpoint discovery: no public server answered');
    return null;
  }

  Future<List<SyncplayEndpoint>> _searchOrder(
    SyncplayEndpoint? preferred,
  ) async {
    final ordered = <SyncplayEndpoint>[];
    void add(SyncplayEndpoint? endpoint) {
      if (endpoint == null) return;
      if (!candidates.contains(endpoint)) return;
      if (ordered.contains(endpoint)) return;
      ordered.add(endpoint);
    }

    add(preferred);
    // The remembered winner is a preference for a *new* room. A room that
    // already has an address skips it: two peers whose remembered winners
    // differ would otherwise fall back to different servers and lose each
    // other, which costs more than one extra join.
    if (preferred == null) add(await _remembered());
    candidates.forEach(add);
    return ordered;
  }

  Future<SyncplayEndpoint?> _remembered() async {
    final stored = await settings.get(kSyncplayEndpointSettingKey);
    if (stored == null || stored.isEmpty) return null;
    return SyncplayEndpoint.tryParse(stored);
  }
}

/// Persist [endpoint] as the remembered Start winner when it is a public
/// candidate. Called after a successful lobby Hello so this key matches
/// the live session, including a pinned bare-code join. A self-hosted pin
/// is left alone.
Future<void> rememberPublicSyncplayEndpoint(
  EndpointSettings settings,
  SyncplayEndpoint endpoint, {
  void Function(String line)? onLog,
}) async {
  if (!isPublicSyncplayCandidate(endpoint)) return;
  try {
    await settings.set(kSyncplayEndpointSettingKey, endpoint.toString());
  } on Object catch (error) {
    // The stored endpoint is a cache — losing it costs one extra join next
    // launch. Failing the user's connect over it would cost the session.
    onLog?.call('endpoint discovery: could not remember $endpoint — $error');
  }
}

/// One pinned lobby join. Success writes [kSyncplayEndpointSettingKey] when
/// the endpoint is a public candidate. A refused or failed Hello does not.
Future<SyncedJoinOutcome> joinPinnedEndpoint({
  required RoomConfig config,
  required EndpointSettings settings,
  required SyncplayClient Function() createClient,
  required Future<String?> Function(
    SyncplayClient client,
    SyncplayEndpoint endpoint,
  )
  connectUntilJoin,
  void Function(String line)? onLog,
}) async {
  final client = createClient();
  final endpoint = SyncplayEndpoint(host: config.server, port: config.port);
  final error = await connectUntilJoin(client, endpoint);
  if (error == null) {
    await rememberPublicSyncplayEndpoint(settings, endpoint, onLog: onLog);
    return SyncedJoinOutcome.ok(
      PublicEndpointJoin(client: client, endpoint: endpoint, config: config),
    );
  }
  return SyncedJoinOutcome.fail(error, retainedClient: client);
}

/// Real-join walk used by the lobby and by Continue Watching.
///
/// [connectUntilJoin] is the same #265 handshake the session uses. Success
/// keeps that client. Anything short of a secure Hello disposes it and tries
/// the next candidate. A Hello that then refuses the room stops the walk.
Future<SyncedJoinOutcome> joinFirstWorkingEndpoint({
  required RoomConfig config,
  required EndpointSettings settings,
  required SyncplayClient Function() createClient,
  required Future<String?> Function(
    SyncplayClient client,
    SyncplayEndpoint endpoint,
  )
  connectUntilJoin,
  List<SyncplayEndpoint> candidates = kPublicSyncplayEndpoints,
  void Function(String line)? onLog,
}) async {
  final discovery = SyncplayEndpointDiscovery(
    settings: settings,
    candidates: candidates,
    onLog: onLog,
  );
  final preferred = switch (config.endpointPolicy) {
    SyncplayEndpointPolicy.discoverFromRoom => SyncplayEndpoint(
      host: config.server,
      port: config.port,
    ),
    SyncplayEndpointPolicy.discover || SyncplayEndpointPolicy.pinned => null,
  };

  SyncplayClient? winner;
  String? refused;

  final endpoint = await discovery.walk(
    preferred: preferred,
    attempt: (candidate) async {
      final client = createClient();
      try {
        final error = await connectUntilJoin(client, candidate);
        if (error == null) {
          winner = client;
          return EndpointWalkDecision.success;
        }
        if (client.hasCompletedHello) {
          refused = error;
          // Keep the client: connectUntilJoin may already have handed it
          // to HomeScreen so a following Error is not dropped (#265).
          winner = client;
          return EndpointWalkDecision.stop;
        }
        return EndpointWalkDecision.next;
      } finally {
        if (!identical(winner, client)) {
          await client.dispose();
        }
      }
    },
  );

  if (winner != null && endpoint != null) {
    return SyncedJoinOutcome.ok(
      PublicEndpointJoin(
        client: winner!,
        endpoint: endpoint,
        config: config.copyWith(server: endpoint.host, port: endpoint.port),
      ),
    );
  }
  return SyncedJoinOutcome.fail(
    refused ?? kNoSyncplayServerMessage,
    retainedClient: endpoint == null ? winner : null,
  );
}
