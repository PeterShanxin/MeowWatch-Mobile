import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Serializes window changes across room replacement and rapid user actions.
abstract final class ImmersiveMode {
  static const _channel = MethodChannel('com.meowwatch.mobile/fullscreen');
  static Future<void>? _pending;

  static Future<void> setEnabled(bool enabled) {
    Future<void> apply() => _apply(enabled).timeout(const Duration(seconds: 3));
    final operation = _pending?.then((_) => apply()) ?? apply();
    // A failed entry must not prevent a later exit from restoring the window.
    final tail = operation.catchError((Object _) {});
    _pending = tail;
    unawaited(
      tail.then((_) {
        if (identical(_pending, tail)) _pending = null;
      }),
    );
    return operation;
  }

  static Future<void> _apply(bool enabled) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // The native bridge also supports Android's enforced edge-to-edge mode.
      await _channel.invokeMethod<void>('setEnabled', enabled);
    } else {
      await SystemChrome.setEnabledSystemUIMode(
        enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
  }
}
