import 'package:meta/meta.dart';

@immutable
class MediaItem {
  const MediaItem({required this.uri, required this.title, this.sizeBytes});

  final Uri uri;
  final String title;
  final int? sizeBytes;
  bool get isNetwork => uri.scheme == 'https' || uri.scheme == 'http';

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
  };

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
    uri: Uri.parse(json['uri'] as String),
    title: json['title'] as String,
    sizeBytes: json['sizeBytes'] as int?,
  );
}
