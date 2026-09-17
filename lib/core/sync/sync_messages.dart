import 'dart:convert';

import 'syncplay_constants.dart';
import 'peer_state.dart';

/// Thrown by [LineFramer.addChunk] when the peer keeps streaming bytes without
/// ever terminating a line — the guard against a hostile or broken server
/// forcing unbounded buffering (#187). The framer clears its buffer before
/// throwing; the caller should treat the connection as dead.
class LineOverflowException implements Exception {
  const LineOverflowException({
    required this.bufferedBytes,
    required this.maxLineBytes,
  });

  final int bufferedBytes;
  final int maxLineBytes;

  @override
  String toString() =>
      'LineOverflowException: line overflow — $bufferedBytes bytes buffered '
      'with no newline (cap $maxLineBytes)';
}

/// Buffers raw socket bytes and yields complete lines. The Syncplay protocol
/// sends one JSON object per line terminated by `\r\n`; we also tolerate a lone
/// `\n`. A partial line may buffer at most [maxLineBytes] before [addChunk]
/// throws [LineOverflowException] — real protocol lines are a few KB at most,
/// so only a hostile or broken peer ever gets near the cap.
class LineFramer {
  LineFramer({this.maxLineBytes = defaultMaxLineBytes});

  /// Generous vs. real Syncplay lines (a full room roster with long file names
  /// is still a few KB), tiny vs. the unbounded growth it prevents.
  static const int defaultMaxLineBytes = 64 * 1024;

  /// Cap on the unconsumed partial line; injectable for tests.
  final int maxLineBytes;

  final List<int> _buffer = <int>[];

  List<String> addChunk(List<int> chunk) {
    _buffer.addAll(chunk);
    final lines = <String>[];
    var start = 0;
    for (var i = 0; i < _buffer.length; i++) {
      if (_buffer[i] == 0x0A) {
        // newline
        var end = i;
        if (end > start && _buffer[end - 1] == 0x0D) {
          end -= 1; // strip preceding carriage return
        }
        lines.add(utf8.decode(_buffer.sublist(start, end)));
        start = i + 1;
      }
    }
    _buffer.removeRange(0, start);
    if (_buffer.length > maxLineBytes) {
      final buffered = _buffer.length;
      _buffer.clear();
      throw LineOverflowException(
        bufferedBytes: buffered,
        maxLineBytes: maxLineBytes,
      );
    }
    return lines;
  }

  /// Discard any partially-buffered line. Call before a reconnect so a stray
  /// half-line from the dead socket can't corrupt the first frame of the new one.
  void reset() => _buffer.clear();
}

// ---------------------------------------------------------------------------
// Encoders — each returns the Map to be json.encode()'d and written as a line.
// ---------------------------------------------------------------------------

/// JSON for an outbound [message] with secrets masked, so they never reach the
/// persistent / exportable diagnostic log. The real wire bytes are encoded
/// separately and keep the secrets. Masks two things:
/// - any `password` value (the room password in the Hello), and
/// - the query string / userinfo of any `http(s)` URL string (a pasted stream
///   link's signed CDN token), since a URL becomes the shared file name and is
///   logged on every announce.
String redactSecretsForLog(Map<String, Object?> message) =>
    json.encode(_scrubForLog(message));

/// As [redactSecretsForLog] but for an already-encoded JSON [line] (e.g. an
/// inbound message we log verbatim). Falls back to the raw line if it isn't a
/// JSON object, so logging never throws on a malformed frame.
String redactSecretsForLogText(String line) {
  Object? decoded;
  try {
    decoded = json.decode(line);
  } on FormatException {
    return line;
  }
  if (decoded is Map) return json.encode(_scrubForLog(decoded));
  return line;
}

Object? _scrubForLog(Object? value) {
  if (value is Map) {
    return <Object?, Object?>{
      for (final entry in value.entries)
        entry.key: entry.key == 'password' ? '***' : _scrubForLog(entry.value),
    };
  }
  if (value is List) return value.map(_scrubForLog).toList();
  if (value is String) return redactUrlSecrets(value);
  return value;
}

/// Strip the query string, userinfo, and fragment from an `http(s)` URL so a
/// signed token can't land in the diagnostic log; leaves non-URL strings
/// untouched. The scheme/host/path stay so the stream is still identifiable in
/// logs. A credential can ride in any of the three — e.g. `?token=…`,
/// `user:pass@host`, or `#token=…` — so all three are dropped.
final RegExp _httpUrlRun = RegExp(r'https?://\S+', caseSensitive: false);

String redactUrlSecrets(String value) {
  return value.replaceAllMapped(
    _httpUrlRun,
    (match) => _redactUrl(match.group(0)!),
  );
}

String _redactUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return value;
  if (uri.scheme != 'http' && uri.scheme != 'https') return value;
  if (uri.host.isEmpty) return value;
  if (uri.query.isEmpty && uri.userInfo.isEmpty && uri.fragment.isEmpty) {
    return value;
  }
  final buffer = StringBuffer('${uri.scheme}://${uri.host}');
  if (uri.hasPort) buffer.write(':${uri.port}');
  buffer.write(uri.path);
  if (uri.query.isNotEmpty) buffer.write('?<redacted>');
  if (uri.fragment.isNotEmpty) buffer.write('#<redacted>');
  return buffer.toString();
}

Map<String, Object?> encodeHello({
  required String username,
  required String room,
  String? password,
}) {
  final hello = <String, Object?>{
    'username': username,
    'room': {'name': room},
    'version': SyncplayConstants.protocolVersion,
    'realversion': SyncplayConstants.realVersion,
    'features': SyncplayConstants.features,
  };
  if (password != null && password.isNotEmpty) {
    hello['password'] = password;
  }
  return {'Hello': hello};
}

Map<String, Object?> encodeFile({
  required String name,
  required int sizeBytes,
  required Duration duration,
}) {
  return {
    'Set': {
      'file': {
        'name': name,
        'duration': duration.inMilliseconds / 1000.0,
        'size': sizeBytes,
      },
    },
  };
}

Map<String, Object?> encodeTlsRequest() => {
  'TLS': {'startTLS': 'send'},
};

Map<String, Object?> encodeChat(String text) => {'Chat': text};

Map<String, Object?> encodeList() => {'List': null};

Map<String, Object?> encodeState({
  required Duration position,
  required bool paused,
  required bool doSeek,
  required double? latencyCalculation,
  required double clientLatencyCalculation,
  required double clientRtt,
  required int clientIgnore,
  required int serverIgnore,
}) {
  final playstate = <String, Object?>{
    'position': position.inMilliseconds / 1000.0,
    'paused': paused,
  };
  if (doSeek) playstate['doSeek'] = true;

  final ping = <String, Object?>{
    'clientLatencyCalculation': clientLatencyCalculation,
    'clientRtt': clientRtt,
  };
  if (latencyCalculation != null) {
    ping['latencyCalculation'] = latencyCalculation;
  }

  final state = <String, Object?>{'playstate': playstate, 'ping': ping};

  if (clientIgnore != 0 || serverIgnore != 0) {
    final ignore = <String, Object?>{};
    if (serverIgnore != 0) ignore['server'] = serverIgnore;
    if (clientIgnore != 0) ignore['client'] = clientIgnore;
    state['ignoringOnTheFly'] = ignore;
  }

  return {'State': state};
}

// ---------------------------------------------------------------------------
// Decoder — classify an incoming parsed Map into a typed ServerMessage.
// ---------------------------------------------------------------------------

sealed class ServerMessage {
  const ServerMessage();
}

class HelloMessage extends ServerMessage {
  const HelloMessage({this.username});

  /// The username the server assigned us. Usually the one we requested, but the
  /// server appends a suffix to dodge a collision ("meow" -> "meow_"); adopting
  /// it keeps our self-identity aligned with what peers and the chat echo see.
  /// Null when the reply carried no username.
  final String? username;
}

class StateMessage extends ServerMessage {
  const StateMessage({
    this.peer,
    this.latencyCalculation,
    this.clientLatencyCalculation,
    this.clientIgnore,
    this.serverIgnore,
  });

  /// Peer playstate, or null if this State carried no playstate block.
  final PeerPlayState? peer;

  /// The server's own timestamp; we echo it back so the server can measure its
  /// RTT to us.
  final double? latencyCalculation;

  /// Our previously sent timestamp, echoed back by the server, so we can
  /// measure our own RTT (now - this).
  final double? clientLatencyCalculation;

  final int? clientIgnore;
  final int? serverIgnore;
}

class PresenceMessage extends ServerMessage {
  const PresenceMessage(this.events, {this.files = const []});
  final List<PresenceEvent> events;

  /// Files announced in the same Set (e.g. a peer joining with a file already
  /// loaded carries both its join event and its file).
  final List<PeerFile> files;
}

/// One or more peers announced (or changed) the file they have loaded.
class PeerFileMessage extends ServerMessage {
  const PeerFileMessage(this.files);
  final List<PeerFile> files;
}

class ChatServerMessage extends ServerMessage {
  const ChatServerMessage(this.message);
  final ChatMessage message;
}

class TlsMessage extends ServerMessage {
  const TlsMessage({required this.startTls});
  final bool startTls;
}

class ErrorMessage extends ServerMessage {
  const ErrorMessage(this.message);
  final String message;
}

/// The full room roster sent by the server (in response to our List, and on
/// joins). Used to learn about users who were already present before us.
class RosterMessage extends ServerMessage {
  const RosterMessage(this.usernames, {this.files = const []});
  final List<String> usernames;
  final List<PeerFile> files;
}

class UnknownMessage extends ServerMessage {
  const UnknownMessage();
}

ServerMessage decodeServerMessage(
  Map<dynamic, dynamic> message, {
  String? selfRoom,
}) {
  if (message.containsKey('Hello')) {
    final hello = message['Hello'];
    final name = hello is Map ? hello['username'] : null;
    return HelloMessage(
      username: name is String && name.isNotEmpty ? name : null,
    );
  }
  if (message.containsKey('State')) {
    return _decodeState(message['State'] as Map);
  }
  if (message.containsKey('Set')) return _decodeSet(message['Set'] as Map);
  if (message.containsKey('List')) {
    return _decodeList(message['List'], selfRoom: selfRoom);
  }
  if (message.containsKey('Chat')) {
    final chat = message['Chat'] as Map;
    return ChatServerMessage(
      ChatMessage(
        username: chat['username'] as String? ?? '',
        text: chat['message'] as String? ?? '',
      ),
    );
  }
  if (message.containsKey('TLS')) {
    final tls = message['TLS'] as Map;
    final answer = tls['startTLS'];
    return TlsMessage(startTls: answer is String && answer.contains('true'));
  }
  if (message.containsKey('Error')) {
    final err = message['Error'] as Map;
    return ErrorMessage(err['message'] as String? ?? 'unknown error');
  }
  return const UnknownMessage();
}

StateMessage _decodeState(Map<dynamic, dynamic> state) {
  PeerPlayState? peer;
  if (state['playstate'] is Map) {
    final ps = state['playstate'] as Map;
    final pos = ps['position'];
    final paused = ps['paused'];
    if (pos is num && paused is bool) {
      peer = PeerPlayState.fromSeconds(
        seconds: pos.toDouble(),
        paused: paused,
        doSeek: ps['doSeek'] == true,
        setBy: ps['setBy'] as String?,
      );
    }
  }
  double? latency;
  double? clientLatency;
  if (state['ping'] is Map) {
    final ping = state['ping'] as Map;
    final lc = ping['latencyCalculation'];
    if (lc is num) latency = lc.toDouble();
    final clc = ping['clientLatencyCalculation'];
    if (clc is num) clientLatency = clc.toDouble();
  }
  int? clientIgnore;
  int? serverIgnore;
  if (state['ignoringOnTheFly'] is Map) {
    final ig = state['ignoringOnTheFly'] as Map;
    if (ig['client'] is num) clientIgnore = (ig['client'] as num).toInt();
    if (ig['server'] is num) serverIgnore = (ig['server'] as num).toInt();
  }
  return StateMessage(
    peer: peer,
    latencyCalculation: latency,
    clientLatencyCalculation: clientLatency,
    clientIgnore: clientIgnore,
    serverIgnore: serverIgnore,
  );
}

/// Parse a `file` block (`{name, size, duration}`) for [username]; null if the
/// entry carries no usable file name.
PeerFile? _parsePeerFile(String username, Object? fileValue) {
  if (fileValue is! Map) return null;
  final name = fileValue['name'];
  if (name is! String || name.isEmpty) return null;
  final size = fileValue['size'];
  final dur = fileValue['duration'];
  return PeerFile(
    username: username,
    name: name,
    sizeBytes: size is num ? size.toInt() : null,
    duration: dur is num
        ? Duration(milliseconds: (dur.toDouble() * 1000).round())
        : null,
  );
}

ServerMessage _decodeList(Object? list, {String? selfRoom}) {
  // Shape: {"List": {roomName: {username: {file: {...}, ...}}}}. Public servers
  // host many rooms; when [selfRoom] is given, only that room's members count as
  // peers — otherwise B would treat strangers in other rooms as "friends".
  final names = <String>[];
  final files = <PeerFile>[];
  if (list is Map) {
    list.forEach((roomName, room) {
      if (room is! Map) return;
      if (selfRoom != null && roomName != selfRoom) return;
      room.forEach((name, entry) {
        if (name is! String) return;
        names.add(name);
        if (entry is Map) {
          final file = _parsePeerFile(name, entry['file']);
          if (file != null) files.add(file);
        }
      });
    });
  }
  return RosterMessage(names, files: files);
}

ServerMessage _decodeSet(Map<dynamic, dynamic> set) {
  if (set['user'] is Map) {
    final events = <PresenceEvent>[];
    final files = <PeerFile>[];
    (set['user'] as Map).forEach((name, value) {
      if (value is! Map || name is! String) return;
      final room = value['room'] is Map
          ? (value['room'] as Map)['name'] as String?
          : null;
      final file = _parsePeerFile(name, value['file']);
      if (file != null) files.add(file);
      final event = value['event'];
      if (event is Map && event['left'] != null) {
        events.add(
          PresenceEvent(
            username: name,
            kind: PresenceKind.left,
            room: room,
            fileName: file?.name,
          ),
        );
      } else if (event is Map && event['joined'] != null) {
        events.add(
          PresenceEvent(
            username: name,
            kind: PresenceKind.joined,
            room: room,
            fileName: file?.name,
          ),
        );
      }
    });
    if (events.isNotEmpty) return PresenceMessage(events, files: files);
    if (files.isNotEmpty) return PeerFileMessage(files);
  }
  return const UnknownMessage();
}
