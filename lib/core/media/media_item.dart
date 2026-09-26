import 'package:meta/meta.dart';

@immutable
class MediaItem {
  const MediaItem({
    required this.uri,
    required this.title,
    this.sizeBytes,
    this.canRemember = true,
  });

  final Uri uri;
  final String title;
  final int? sizeBytes;

  /// Temporary Android share grants must not create unusable resume entries.
  final bool canRemember;
  bool get isNetwork => uri.scheme == 'https' || uri.scheme == 'http';

  /// The name announced to Syncplay peers for file-mismatch detection.
  /// Network media announces its full URL — desktop's `compareFiles` (and
  /// stock Syncplay) identify a stream by its whole link, since a basename
  /// like `movie.mp4` or `index.m3u8` alone cannot disambiguate two different
  /// streams. Local files keep announcing their [title].
  String get announcedName => isNetwork ? uri.toString() : title;

  factory MediaItem.fromUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('Paste a direct HTTP or HTTPS video link.');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'Links containing a username or password are not supported.',
      );
    }
    final host = uri.host.toLowerCase();
    if ([
      'youtube.com',
      'youtu.be',
      'netflix.com',
      'disneyplus.com',
      'primevideo.com',
    ].any((site) => host == site || host.endsWith('.$site'))) {
      throw const FormatException(
        'This is a webpage, not a direct video. Choose a video file or a direct media link. Protected streaming services are not supported.',
      );
    }
    final name = uri.pathSegments.isEmpty ? uri.host : uri.pathSegments.last;
    return MediaItem(uri: uri, title: name.isEmpty ? uri.host : name);
  }

  Map<String, Object?> toJson() => {
    'uri': uri.toString(),
    'title': title,
    'sizeBytes': sizeBytes,
    'canRemember': canRemember,
  };

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
    uri: Uri.parse(json['uri'] as String),
    title: json['title'] as String,
    sizeBytes: json['sizeBytes'] as int?,
    canRemember: json['canRemember'] as bool? ?? true,
  );
}
