import 'package:flutter/services.dart';

/// The Android framework owns receiver discovery and the Cast protocol.
abstract interface class CastTransport {
  Stream<Map<Object?, Object?>> get events;
  Future<Map<Object?, Object?>> invoke(
    String method, [
    Map<String, Object?> arguments = const {},
  ]);
}

class AndroidCastTransport implements CastTransport {
  static const _methods = MethodChannel('com.meowwatch.mobile/cast');
  static const _events = EventChannel('com.meowwatch.mobile/cast/events');
  // One underlying platform subscription: retiring one target must not remove
  // another target's channel handler or cancel the native event sink.
  static final _sharedEvents = _events.receiveBroadcastStream().map(
    (event) => Map<Object?, Object?>.from(event as Map),
  );

  @override
  Stream<Map<Object?, Object?>> get events => _sharedEvents;

  @override
  Future<Map<Object?, Object?>> invoke(
    String method, [
    Map<String, Object?> arguments = const {},
  ]) async =>
      await _methods.invokeMapMethod<Object?, Object?>(method, arguments) ??
      const {};
}
