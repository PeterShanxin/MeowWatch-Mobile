import 'dart:async';

import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/sync_core.dart';

class SyncTestTarget extends PlaybackTarget {
  final _states = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  PlaybackSnapshot _snapshot = const PlaybackSnapshot();
  final commands = <String>[];
  Completer<void>? seekGate;
  Completer<void>? loadGate;
  bool throwSeek = false;
  int _generation = 0;
  @override
  String get id => 'test';
  @override
  String get label => 'Test target';
  @override
  PlaybackSnapshot get snapshot => _snapshot;
  @override
  Stream<PlaybackSnapshot> get states => _states.stream;

  void emit(PlaybackSnapshot value) {
    _snapshot = value;
    _states.add(value);
  }

  void _set({Duration? position, bool? playing}) => emit(
    PlaybackSnapshot(
      media: _snapshot.media,
      position: position ?? _snapshot.position,
      playing: playing ?? _snapshot.playing,
      duration: _snapshot.duration,
      connection: _snapshot.connection,
    ),
  );

  @override
  Future<void> load(
    MediaItem media, {
    Duration position = Duration.zero,
  }) async {
    final generation = ++_generation;
    final gate = loadGate;
    loadGate = null;
    emit(
      PlaybackSnapshot(media: media, connection: PlaybackConnection.loading),
    );
    await gate?.future;
    if (generation != _generation) return;
    emit(
      PlaybackSnapshot(
        media: media,
        position: position,
        duration: const Duration(minutes: 5),
        connection: PlaybackConnection.ready,
      ),
    );
  }

  @override
  Future<void> play() async {
    commands.add('play');
    _set(playing: true);
  }

  @override
  Future<void> pause() async {
    commands.add('pause');
    _set(playing: false);
  }

  @override
  Future<void> seek(Duration position) async {
    commands.add('seek:${position.inMilliseconds}');
    final generation = _generation;
    final gate = seekGate;
    seekGate = null;
    await gate?.future;
    if (generation != _generation) return;
    if (throwSeek) throw StateError('native seek failed');
    _set(position: position);
  }

  @override
  Future<void> close() async {
    _generation++;
    await _states.close();
  }
}

class SyncTestCore extends SyncCore {
  final published = <PeerPlayState>[];
  final changes = <bool>[];
  final announced = <String>[];
  void peer(PeerPlayState state) {
    lastObservedRoomState = state;
    emitPeerState(state);
  }

  void connection(SyncConnectionStatus status) =>
      emitConnectionState(SyncConnectionState(status: status));
  @override
  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  }) async {}
  @override
  Future<void> disconnect() async =>
      connection(SyncConnectionStatus.disconnected);
  @override
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  }) => announced.add(name);
  @override
  void notifyLocalChange({required bool doSeek}) => changes.add(doSeek);
  @override
  void updateLocalState({required Duration position, required bool paused}) =>
      published.add(PeerPlayState(position: position, paused: paused));
  @override
  void sendChat(String text) {}
  @override
  Future<void> disposeBackend() async {}
}
