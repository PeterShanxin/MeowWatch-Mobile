import '../media/media_item.dart';

/// Recognizes a deliberately shared, standalone media URL without fetching it.
/// Prose, webpages and ambiguous messages remain ordinary chat.
MediaItem? sharedVideoLink(String message) {
  if (message.length > 2048) return null;
  final value = message.trim();
  if (value.isEmpty ||
      RegExp(
        r'[\s\x00-\x20\x7f-\x9f<>"\\\u200b-\u200f\u202a-\u202e\u2060-\u206f]',
      ).hasMatch(value) ||
      RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(value) ||
      RegExp(r'^https?://[^/?#]*@', caseSensitive: false).hasMatch(value) ||
      RegExp(r'https?://', caseSensitive: false).allMatches(value).length !=
          1) {
    return null;
  }
  try {
    final media = MediaItem.fromUrl(value);
    final uri = media.uri;
    if (!uri.hasAuthority ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.authority.contains('@') ||
        !RegExp(r'^[a-zA-Z0-9.\-:\[\]]+$').hasMatch(uri.host) ||
        uri.host.startsWith('.') ||
        uri.host.contains('..') ||
        !RegExp(
          r'\.(mp4|m4v|webm|mov|mkv|m3u8|mpd)$',
          caseSensitive: false,
        ).hasMatch(uri.path)) {
      return null;
    }
    // Uri permits some non-DNS reg-names; offer only conventional hostnames
    // (or IPv6 literals, already validated by Uri) in this peer entry point.
    if (!uri.host.contains(':') &&
        !RegExp(
          r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.?$',
        ).hasMatch(uri.host)) {
      return null;
    }
    final decodedPath = Uri.decodeComponent(uri.path);
    if (RegExp(
      r'[\x00-\x1f\x7f-\x9f\u200b-\u200f\u202a-\u202e\u2060-\u206f]',
    ).hasMatch(decodedPath)) {
      return null;
    }
    return media;
  } on FormatException {
    return null;
  }
}
