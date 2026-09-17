/// Wire-protocol constants for the Syncplay client, verified against upstream
/// syncplay/constants.py (May 2026).
class SyncplayConstants {
  SyncplayConstants._();

  /// Sent as `version` in Hello for backward compat; real version goes in
  /// `realversion`. Upstream clients do exactly this.
  static const protocolVersion = '1.2.255';
  static const realVersion = '1.7.5';

  static const defaultServer = 'syncplay.pl';
  static const defaultPort = 8999;
  static const publicServerPort = 8995;

  /// Max displayed characters per chat message (upstream
  /// `MAX_CHAT_MESSAGE_LENGTH = 150`). The server silently truncates anything
  /// longer, so we cap the composer at the same limit with a visible counter —
  /// mirroring the official client — so nothing is lost without the user seeing
  /// it (#55).
  static const maxChatMessageLength = 150;

  /// Feature map advertised in Hello. We support chat receive only this phase,
  /// but advertise the standard static flags so servers treat us as a modern
  /// client.
  static const features = <String, Object>{
    'sharedPlaylists': false,
    'chat': true,
    'featureList': true,
    'readiness': true,
    'managedRooms': true,
    'persistentRooms': true,
    'setOthersReadiness': false,
  };

  /// If the local player runs AHEAD of the room's global position by more than
  /// this, rewind it back to the global position (upstream DEFAULT_REWIND_
  /// THRESHOLD = 4s). One-directional: only the ahead client corrects, which
  /// is what stops two clients fighting over position.
  static const rewindThreshold = Duration(seconds: 4);

  /// Below this, a local position change is treated as natural playback drift
  /// rather than a user seek when deciding what to broadcast.
  static const seekDetectThreshold = Duration(milliseconds: 1000);
}
