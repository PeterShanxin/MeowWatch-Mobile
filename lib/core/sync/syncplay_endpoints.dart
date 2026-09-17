import 'package:meta/meta.dart';

/// A Syncplay server address MeowWatch can dial.
///
/// Deliberately narrower than the endpoint a share code carries
/// (`core/connect/room_share.dart`): the curated public candidates and the
/// remembered winner are always plain `host:port`, so there is no IPv6-bracket
/// form to parse here. A pasted code still goes through the share-code parser.
@immutable
class SyncplayEndpoint {
  const SyncplayEndpoint({required this.host, required this.port});

  final String host;
  final int port;

  /// The persisted / logged form.
  @override
  String toString() => '$host:$port';

  /// Parses [raw] back from [toString]. Null for anything that is not
  /// `host:port` with an in-range port, so a corrupted or hand-edited settings
  /// row is ignored instead of dialled.
  static SyncplayEndpoint? tryParse(String raw) {
    final text = raw.trim();
    final colon = text.lastIndexOf(':');
    if (colon <= 0 || colon == text.length - 1) return null;
    final host = text.substring(0, colon);
    if (host.contains(':') || host.contains(' ')) return null;
    final port = int.tryParse(text.substring(colon + 1));
    if (port == null || port < 1 || port > 65535) return null;
    return SyncplayEndpoint(host: host, port: port);
  }

  @override
  bool operator ==(Object other) =>
      other is SyncplayEndpoint && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

/// The public Syncplay endpoints MeowWatch picks from when the user has not
/// named one, in the order they are tried.
///
/// Mirrors upstream Syncplay's own public server list
/// (`FALLBACK_PUBLIC_SYNCPLAY_SERVERS` in `syncplay/constants.py`, and what
/// `https://syncplay.pl/listpublicservers` serves) as of September 2026: one
/// host exposing five ports. The ports are separate candidates because a host
/// can be up while one port is firewalled or retired — which is the outage
/// this list exists to survive (#234).
///
/// The order is fixed and shared by every install. That is what lets two peers
/// resolve the same endpoint independently: given the same starting point they
/// walk the same list and stop at the same entry.
const List<SyncplayEndpoint> kPublicSyncplayEndpoints = <SyncplayEndpoint>[
  SyncplayEndpoint(host: 'syncplay.pl', port: 8995),
  SyncplayEndpoint(host: 'syncplay.pl', port: 8996),
  SyncplayEndpoint(host: 'syncplay.pl', port: 8997),
  SyncplayEndpoint(host: 'syncplay.pl', port: 8998),
  SyncplayEndpoint(host: 'syncplay.pl', port: 8999),
];

/// Whether [endpoint] is one MeowWatch chose for the user, rather than one the
/// user (or a friend's code) named.
///
/// This is the line between "app-managed, may be re-resolved when it dies" and
/// "the user's own server, never touched". A self-hosted host is never in the
/// curated list, so it is never a candidate for replacement.
bool isPublicSyncplayCandidate(SyncplayEndpoint endpoint) =>
    kPublicSyncplayEndpoints.contains(endpoint);
