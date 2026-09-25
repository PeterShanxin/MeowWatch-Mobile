/// Result of comparing the locally loaded file to a peer's announced file.
enum FileMatch {
  /// Not enough info yet (one side hasn't announced a file).
  unknown,

  /// The files look like the same media.
  match,

  /// The files clearly differ — warn the watchers.
  mismatch,
}

/// Decide whether the local file and a peer's file are the same media.
///
/// Byte size is the strongest signal: the same file is the same number of
/// bytes, regardless of filename. So when both sizes are known we trust them
/// outright. When size is unavailable we fall back to a normalized filename
/// comparison. With neither comparable, the result is [FileMatch.unknown] (no
/// warning — better silent than crying wolf).
FileMatch compareFiles({
  String? localName,
  int? localSize,
  String? peerName,
  int? peerSize,
}) {
  final haveLocal =
      (localName != null && localName.isNotEmpty) ||
      (localSize != null && localSize > 0);
  final havePeer =
      (peerName != null && peerName.isNotEmpty) ||
      (peerSize != null && peerSize > 0);
  if (!haveLocal || !havePeer) return FileMatch.unknown;

  // Strongest: byte size when both sides report it.
  if (localSize != null && localSize > 0 && peerSize != null && peerSize > 0) {
    return localSize == peerSize ? FileMatch.match : FileMatch.mismatch;
  }

  // A stream is identified by its URL (size is always 0), so when either side
  // is a URL compare the *whole* link — never the basename. Otherwise two
  // different streams that happen to end in a generic name (`master.m3u8`,
  // `index.m3u8`, `video.mp4`) would falsely read as the same media.
  final localUrl = _asUrl(localName);
  final peerUrl = _asUrl(peerName);
  if (localUrl != null || peerUrl != null) {
    if (localUrl == null || peerUrl == null) return FileMatch.mismatch;
    return localUrl == peerUrl ? FileMatch.match : FileMatch.mismatch;
  }

  // Fallback: normalized filename.
  final ln = _normalize(localName);
  final pn = _normalize(peerName);
  if (ln.isNotEmpty && pn.isNotEmpty) {
    return ln == pn ? FileMatch.match : FileMatch.mismatch;
  }

  return FileMatch.unknown;
}

/// The normalized `http(s)` URL form of [name], or `null` if it isn't a URL.
/// Lets [compareFiles] compare stream links whole instead of by basename.
///
/// `Uri` already lower-cases the case-insensitive parts (scheme + host) while
/// leaving the path and query — which carry case-sensitive segments and signed
/// CDN tokens — untouched, so two links that differ only in a token still read
/// as different media.
String? _asUrl(String? name) {
  if (name == null) return null;
  final uri = Uri.tryParse(name.trim());
  if (uri == null) return null;
  final isUrl =
      (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  return isUrl ? uri.toString() : null;
}

/// Lower-cased base filename — strips any directory part so a full path on one
/// side and a bare filename on the other still compare equal.
String _normalize(String? name) {
  if (name == null) return '';
  final base = name.split(RegExp(r'[/\\]')).last;
  return base.trim().toLowerCase();
}
