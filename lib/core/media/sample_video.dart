import 'media_item.dart';

/// The unmodified, publicly hosted Blender Foundation trailer.
const sampleVideoUrl =
    'https://download.blender.org/durian/trailer/sintel_trailer-480p.mp4';
const sampleVideoTitle = 'Sintel — official trailer';
const sampleVideoCredit = '© Blender Foundation · sintel.org · CC BY 3.0';
const sampleVideoLicenseUrl = 'https://durian.blender.org/sharing/';

MediaItem sampleVideo() =>
    MediaItem(uri: Uri.parse(sampleVideoUrl), title: sampleVideoTitle);
