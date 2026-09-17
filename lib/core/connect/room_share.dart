import 'package:meta/meta.dart';

import '../sync/syncplay_constants.dart';

/// Turns a room + its connection settings into a single, copy-pasteable
/// **share code**, and parses one back. This is what makes a magic sentence
/// *self-contained* (#110): when the host is on a non-default server, the code
/// carries the server address so a friend joins from one paste.
///
/// ## Shape
/// On the default public server the code stays the bare magic sentence, so the
/// common case is unchanged and short:
///
///   `sleepy-otter-counts-cozy-stars`
///
/// When the server or port differ from the public defaults, the endpoint is
/// appended URL-style, always with an explicit port (the `:` is the
/// unambiguous marker):
///
///   `sleepy-otter-counts-cozy-stars@cozy.example.net:8999`    (custom host)
///   `sleepy-otter-counts-cozy-stars@cozy.example.net:9000`    (custom host+port)
///   `sleepy-otter-counts-cozy-stars@syncplay.pl:9000`         (custom port only)
///   `sleepy-otter-counts-cozy-stars@[2001:db8::1]:8999`       (IPv6 literal)
///
/// ## No password, ever
/// The Advanced *server* password is deliberately NOT encoded. A cipher would
/// be a fake lock: the app must decode the code to use it, so the key has to
/// ship inside the (open-source) binary — any onlooker's copy could decode it
/// too. There is no real encryption possible for a paste-anywhere code, so the
/// only secret stays out. Server + port aren't secret, so they ride along; a
/// self-hosted server password is typed once into Advanced by the joiner.
///
/// ## Backward compatibility
/// A string with no `@` — or one whose tail after `@` doesn't look like a
/// server endpoint (e.g. a manual room literally named `movie@home` or
/// `movie@example.com`) — is treated as a plain room name. Old room-only codes
/// (`happy-cat-11`), folded `happy-cat-11-k3pn` codes, and every magic sentence
/// fall here and join verbatim against the first public candidate. The split
/// only fires when the tail carries a `:` (the host:port separator the
/// encoder always emits) or
/// is a bracketed IPv6 literal — neither of which a magic sentence contains.
///
/// ## Known limitation (accepted)
/// URL-style sharing is inherently ambiguous for a *manually-named* room shaped
/// exactly like a code, e.g. a default-server room literally named
/// `movie@home:9000`: it's indistinguishable from room `movie` on `home:9000`,
/// and disambiguating it would conflict with supporting real single-label
/// servers (`room@myserver:8999`). Fully resolving it would require a version
/// marker or percent-escaping — a product decision taken against in favour of
/// short, readable codes. This never affects generated codes or any old code
/// (none contain `@`); it only touches deliberately hand-typed names, which
/// stay joinable via the room field. See issue #110.

/// Shown when a structured code (`room@…`) is present but malformed, so the
/// joiner gets clear feedback instead of a confusing failed join into a garbage
/// room name.
const String malformedShareCodeMessage =
    'That code looks off — ask your friend to copy and paste it again.';

/// The result of [parseShareCode]: the bare [room] to join plus any [server] /
/// [port] the code carried. [server]/[port] are null when the code didn't
/// specify them (the caller pins a bare code to the first public candidate).
/// When [error] is non-null the code was structured but malformed and must
/// NOT be used to join.
@immutable
class ParsedShareCode {
  const ParsedShareCode({
    required this.room,
    this.server,
    this.port,
    this.error,
  });

  final String room;
  final String? server;
  final int? port;
  final String? error;

  bool get isValid => error == null;

  @override
  bool operator ==(Object other) =>
      other is ParsedShareCode &&
      other.room == room &&
      other.server == server &&
      other.port == port &&
      other.error == error;

  @override
  int get hashCode => Object.hash(room, server, port, error);
}

/// Builds the shareable code for [room] given the [server] and [port] it's
/// hosted on. Returns the bare [room] when both are the defaults; otherwise
/// appends `@host:port`, **always including the port**.
///
/// The explicit port is what makes the form unambiguous: a colon never appears
/// in a magic sentence, so "the tail has a colon" cleanly marks a share code
/// and a manual room name that merely contains `@` (even a dotted one like
/// `movie@example.com`) is left to join verbatim. An IPv6 literal host is
/// bracketed (`room@[2001:db8::1]:9000`) so its own colons aren't read as the
/// port separator. Default-server codes stay the bare sentence, so the common
/// case is unaffected; only the already-technical non-default codes carry the
/// port.
String encodeShareCode({
  required String room,
  required String server,
  required int port,
}) {
  final isDefaultServer = server == SyncplayConstants.defaultServer;
  final isPublicPort = port == SyncplayConstants.publicServerPort;
  if (isDefaultServer && isPublicPort) return room;
  return '$room@${_encodeHost(server)}:$port';
}

/// Brackets an IPv6 literal so its colons aren't read as a port separator;
/// leaves an already-bracketed or non-IPv6 host untouched.
String _encodeHost(String server) {
  if (server.startsWith('[')) return server;
  if (server.contains(':')) return '[$server]';
  return server;
}

/// Whether the text after `@` looks like a server endpoint rather than part of
/// a legacy room name that merely contains `@` (e.g. `movie@home` or
/// `movie@example.com`). True only when it's a bracketed IPv6 literal or
/// carries a `:` (the host:port separator our encoder always emits). A `:` with
/// a bad/missing port still counts as endpoint-like so it surfaces clear
/// malformed feedback instead of silently joining a garbage room.
bool _looksLikeEndpoint(String endpoint) =>
    endpoint.startsWith('[') || endpoint.contains(':');

/// Parses a pasted [raw] code into a room + optional server/port.
///
/// - No `@`, or a tail that doesn't look like a server endpoint → the whole
///   string is the room. This keeps old room-only codes (`happy-cat-11`) AND
///   legacy room names that happen to contain `@` (`movie@home`) joining
///   verbatim, exactly like the pre-feature join path.
/// - `room@host`, `room@host:port`, or `room@[ipv6]:port` → room + endpoint.
/// - A tail that looks structured but is broken (bad/out-of-range port, empty
///   host) → [error] ([malformedShareCodeMessage]) so the caller warns instead
///   of joining a garbage room.
///
/// The room/endpoint boundary is the **last** `@`, not the first: a host:port
/// never contains `@`, so the last one is always the real separator. That lets
/// a room name that itself contains `@` (e.g. re-sharing a room joined as
/// `movie@example.com` from a custom server) round-trip correctly instead of
/// being truncated at the first `@`.
ParsedShareCode parseShareCode(String raw) {
  final trimmed = raw.trim();
  final at = trimmed.lastIndexOf('@');
  if (at < 0) return ParsedShareCode(room: trimmed);

  final room = trimmed.substring(0, at);
  final endpoint = trimmed.substring(at + 1);
  // An empty room or a tail that isn't endpoint-like is a plain room name, not
  // one of our share codes — join it verbatim (back-compat).
  if (room.isEmpty || !_looksLikeEndpoint(endpoint)) {
    return ParsedShareCode(room: trimmed);
  }

  final parsed = _parseEndpoint(endpoint);
  if (parsed == null) {
    return ParsedShareCode(room: trimmed, error: malformedShareCodeMessage);
  }
  return ParsedShareCode(room: room, server: parsed.host, port: parsed.port);
}

/// A host + optional port split out of the text after `@`.
class _Endpoint {
  const _Endpoint(this.host, this.port);
  final String host;
  final int? port;
}

/// Splits `host`, `host:port`, `[ipv6]`, or `[ipv6]:port` into its parts, or
/// null when malformed. A bare unbracketed IPv6 (multiple colons, no brackets)
/// is rejected — our encoder always brackets those.
_Endpoint? _parseEndpoint(String endpoint) {
  if (endpoint.startsWith('[')) {
    final close = endpoint.indexOf(']');
    if (close < 0) return null;
    final host = endpoint.substring(1, close);
    final rest = endpoint.substring(close + 1);
    if (host.isEmpty) return null;
    if (rest.isEmpty) return _Endpoint(host, null);
    if (!rest.startsWith(':')) return null;
    final port = _parsePort(rest.substring(1));
    return port == null ? null : _Endpoint(host, port);
  }

  String host = endpoint;
  int? port;
  final colon = endpoint.lastIndexOf(':');
  if (colon >= 0) {
    port = _parsePort(endpoint.substring(colon + 1));
    if (port == null) return null;
    host = endpoint.substring(0, colon);
  }
  // A bare host can't be empty, hold whitespace, or still carry a colon (an
  // unbracketed IPv6 — share those bracketed).
  if (host.isEmpty || host.contains(' ') || host.contains(':')) return null;
  return _Endpoint(host, port);
}

/// Parses a port string, returning null unless it's a valid 1–65535 number.
int? _parsePort(String s) {
  final n = int.tryParse(s);
  if (n == null || n < 1 || n > 65535) return null;
  return n;
}
