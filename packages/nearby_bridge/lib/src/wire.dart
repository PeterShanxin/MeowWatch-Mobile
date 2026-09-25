import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'primitives.dart';

const maxFrameBytes = 64 * 1024;
const maxSafeInteger = 9007199254740991;
const _types = {
  'pair.hello',
  'pair.challenge',
  'pair.proof',
  'pair.pending',
  'pair.accept',
  'auth.hello',
  'auth.challenge',
  'auth.proof',
  'auth.ok',
  'command',
  'result',
  'state.snapshot',
  'chat.message',
  'chat.reaction',
  'chat.typing',
  'presence',
  'ping',
  'pong',
  'error',
};

final class NearbyFrame {
  NearbyFrame(Map<String, Object?> fields) : fields = Map.unmodifiable(fields) {
    if (fields['v'] is! int || fields['v'] != 1) {
      throw const NearbyException('version_unsupported');
    }
    if (!_types.contains(fields['type'])) {
      throw const NearbyException('invalid_argument');
    }
    if (fields['type'] == 'command') _validateCommand(fields);
  }
  final Map<String, Object?> fields;
  String get type => fields['type']! as String;
  @override
  String toString() => 'NearbyFrame($type)';
}

void _validateCommand(Map<String, Object?> frame) {
  final seq = frame['seq'];
  if (seq is! int ||
      seq < 1 ||
      seq > maxSafeInteger ||
      frame['id'] is! String ||
      frame['sessionEpoch'] is! String ||
      (frame['id']! as String).isEmpty ||
      (frame['id']! as String).length > 64 ||
      (frame['sessionEpoch']! as String).isEmpty ||
      (frame['sessionEpoch']! as String).length > 64 ||
      frame['args'] is! Map<String, Object?>) {
    throw const NearbyException('invalid_argument');
  }
  final args = frame['args']! as Map<String, Object?>;
  switch (frame['method']) {
    case 'state.get':
    case 'playback.play':
    case 'playback.pause':
    case 'controller.detach':
    case 'device.revokeSelf':
      if (args.isNotEmpty) throw const NearbyException('invalid_argument');
    case 'playback.seek':
      final position = args['positionMs'];
      if (args.length != 1 ||
          position is! int ||
          position < 0 ||
          position > 7 * 24 * 60 * 60 * 1000) {
        throw const NearbyException('invalid_argument');
      }
    case 'chat.send':
      final text = args['text'];
      if (args.length != 1 ||
          text is! String ||
          text.trim().isEmpty ||
          text.runes.length > 150) {
        throw const NearbyException('invalid_argument');
      }
    case 'chat.reaction':
      if (args.length != 1 ||
          !const {
            '❤️',
            '😂',
            '😮',
            '😢',
            '👏',
            '👍',
          }.contains(args['reaction'])) {
        throw const NearbyException('invalid_argument');
      }
    case 'chat.typing':
      if (args.length != 1 || args['typing'] is! bool) {
        throw const NearbyException('invalid_argument');
      }
    default:
      // Session replacement needs a separately approved application adapter.
      throw const NearbyException('unsupported_command');
  }
}

final class NearbyFrameCodec {
  const NearbyFrameCodec();
  NearbyFrame decode(List<int> bytes) {
    if (bytes.isEmpty ||
        bytes.length > maxFrameBytes ||
        bytes.any((byte) => byte < 0 || byte > 255)) {
      throw const NearbyException('invalid_argument');
    }
    try {
      final parsed = _BoundedJson(utf8.decode(bytes)).parse();
      if (parsed is! Map<String, Object?>) {
        throw const NearbyException('invalid_argument');
      }
      return NearbyFrame(parsed);
    } on NearbyException {
      rethrow;
    } catch (_) {
      throw const NearbyException('invalid_argument');
    }
  }

  Uint8List encode(NearbyFrame frame) {
    try {
      final encoded = utf8.encode(jsonEncode(frame.fields));
      decode(encoded); // Identical inbound/outbound bounds.
      return Uint8List.fromList([...encoded, 10]);
    } on NearbyException {
      rethrow;
    } catch (_) {
      throw const NearbyException('invalid_argument');
    }
  }
}

/// A failed decoder is terminal. The owner must close the underlying socket.
final class JsonLineDecoder
    extends StreamTransformerBase<List<int>, NearbyFrame> {
  const JsonLineDecoder();
  @override
  Stream<NearbyFrame> bind(Stream<List<int>> stream) async* {
    var pending = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      var start = 0;
      for (var i = 0; i < chunk.length; i++) {
        if (chunk[i] != 10) continue;
        if (pending.length + i - start > maxFrameBytes) {
          throw const NearbyException('invalid_argument');
        }
        pending.add(chunk.sublist(start, i));
        yield const NearbyFrameCodec().decode(pending.takeBytes());
        start = i + 1;
      }
      if (pending.length + chunk.length - start > maxFrameBytes) {
        throw const NearbyException('invalid_argument');
      }
      pending.add(chunk.sublist(start));
    }
    if (pending.isNotEmpty) throw const NearbyException('invalid_argument');
  }
}

/// Check before dispatch. Sequence state is discarded when a socket closes.
final class FrameSequence {
  int _last = 0;
  void accept(NearbyFrame frame) {
    final seq = frame.fields['seq'];
    if (seq is! int || seq <= _last || seq > maxSafeInteger) {
      throw const NearbyException('invalid_argument');
    }
    _last = seq;
  }
}

// Parsing bounds are enforced before building arbitrary nested JSON values.
// jsonDecode alone accepts duplicate object keys, so objects are parsed here.
final class _BoundedJson {
  _BoundedJson(this.source);
  final String source;
  int cursor = 0;
  int nodes = 0;
  static final _number = RegExp(
    r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
  );
  Never _invalid() => throw const NearbyException('invalid_argument');
  void _space() {
    while (cursor < source.length &&
        const [9, 10, 13, 32].contains(source.codeUnitAt(cursor))) {
      cursor++;
    }
  }

  bool _take(String character) {
    _space();
    if (cursor < source.length && source[cursor] == character) {
      cursor++;
      return true;
    }
    return false;
  }

  Object? parse() {
    final value = _value(0);
    _space();
    if (cursor != source.length) _invalid();
    return value;
  }

  Object? _value(int depth) {
    if (++nodes > 2048 || depth > 12) _invalid();
    _space();
    if (cursor == source.length) _invalid();
    if (_take('{')) {
      final object = <String, Object?>{};
      if (_take('}')) return Map<String, Object?>.unmodifiable(object);
      do {
        _space();
        final key = _string();
        if (object.length >= 128 || object.containsKey(key) || !_take(':')) {
          _invalid();
        }
        object[key] = _value(depth + 1);
        if (_take('}')) return Map<String, Object?>.unmodifiable(object);
      } while (_take(','));
      _invalid();
    }
    if (_take('[')) {
      final array = <Object?>[];
      if (_take(']')) return List<Object?>.unmodifiable(array);
      do {
        if (array.length >= 256) _invalid();
        array.add(_value(depth + 1));
        if (_take(']')) return List<Object?>.unmodifiable(array);
      } while (_take(','));
      _invalid();
    }
    if (source[cursor] == '"') return _string();
    for (final entry in {'null': null, 'true': true, 'false': false}.entries) {
      if (source.startsWith(entry.key, cursor)) {
        cursor += entry.key.length;
        return entry.value;
      }
    }
    final match = _number.matchAsPrefix(source, cursor);
    if (match == null) _invalid();
    cursor = match.end;
    final number = num.tryParse(match[0]!);
    if (number == null || !number.isFinite || number.abs() > maxSafeInteger) {
      _invalid();
    }
    return number;
  }

  String _string() {
    if (cursor >= source.length || source[cursor] != '"') _invalid();
    final start = cursor++;
    var escaped = false;
    while (cursor < source.length) {
      final c = source[cursor++];
      if (!escaped && c == '"') {
        final value = jsonDecode(source.substring(start, cursor)) as String;
        if (value.length > 4096) _invalid();
        // UTF-8 cannot represent lone surrogates, including JSON \u escapes.
        if (utf8.decode(utf8.encode(value)) != value) _invalid();
        return value;
      }
      if (!escaped && c == '\\') {
        escaped = true;
      } else {
        escaped = false;
      }
    }
    _invalid();
  }
}
