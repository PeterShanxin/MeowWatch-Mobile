import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'media_item.dart';

class MediaPicker {
  static const _channel = MethodChannel('com.meowwatch.mobile/media');

  Future<MediaItem?> pickVideo() async {
    if (Platform.isAndroid) {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'pickVideo',
      );
      if (result == null) return null;
      return MediaItem.fromJson(Map<String, dynamic>.from(result));
    }
    final file = await FilePicker.pickFile(type: FileType.video);
    if (file == null || file.path == null) return null;
    return MediaItem(
      uri: Uri.file(file.path!),
      title: file.name,
      sizeBytes: file.lengthSync(),
    );
  }
}
