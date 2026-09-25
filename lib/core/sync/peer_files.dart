import 'package:meta/meta.dart';

import 'peer_state.dart';

/// Immutable record of the file each peer has announced, keyed by username.
///
/// MeowWatch is a two-person app, but a transient extra member can appear —
/// most notably a stale "ghost" of our own dropped session that the Syncplay
/// server still lists for a few seconds after a fast reconnect. A single peer
/// slot conflated all peers, so that ghost's eventual departure (or its file
/// overwriting ours) made a friend who HAD loaded a video read as "hasn't
/// loaded" (#93). Keying by username fixes that: removing one peer never
/// touches another's file, and [currentAmong] only surfaces a file whose owner
/// is still present, so a departed ghost's lingering entry is ignored.
@immutable
class PeerFiles {
  const PeerFiles([this._byUser = const <String, PeerFile>{}]);

  final Map<String, PeerFile> _byUser;

  /// A new book with [file] recorded for its username (replacing any prior one).
  PeerFiles set(PeerFile file) => PeerFiles({..._byUser, file.username: file});

  /// A new book with [username]'s file forgotten (e.g. they left the room).
  PeerFiles remove(String username) =>
      PeerFiles({..._byUser}..remove(username));

  /// The file of the first still-present peer who has announced one, scanning
  /// [presentPeers] in order; null if no present peer has a file. Restricting to
  /// present peers means a departed ghost whose entry hasn't been pruned yet
  /// never masks the real state.
  PeerFile? currentAmong(Iterable<String> presentPeers) {
    for (final name in presentPeers) {
      final file = _byUser[name];
      if (file != null) return file;
    }
    return null;
  }

  bool get isEmpty => _byUser.isEmpty;
}
