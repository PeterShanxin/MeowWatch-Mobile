import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/chat/chat_signals.dart';
import 'package:meowwatch_mobile/core/chat/chat_store.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/sync_core.dart';

class FakeSync extends SyncCore {
  final List<String> sent = <String>[];

  void incoming(ChatMessage m) => emitChat(m);

  void connectedAs(String username) => emitConnectionState(
    SyncConnectionState(
      status: SyncConnectionStatus.connected,
      username: username,
    ),
  );

  @override
  Future<void> connect({
    required String server,
    required int port,
    required String username,
    required String room,
    String? password,
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  void announceFile({
    required String name,
    required int size,
    required Duration duration,
  }) {}

  @override
  void updateLocalState({required Duration position, required bool paused}) {}

  @override
  void notifyLocalChange({required bool doSeek}) {}

  @override
  void sendChat(String text) => sent.add(text);

  @override
  Future<void> disposeBackend() async {}
}

void main() {
  test('appends incoming messages in order', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);

    sync.incoming(const ChatMessage(username: 'lin', text: 'hi'));
    sync.incoming(const ChatMessage(username: 'me', text: 'yo'));
    await Future<void>.delayed(Duration.zero);

    expect(store.messages.map((m) => m.text), ['hi', 'yo']);
    await store.dispose();
    await sync.dispose();
  });

  test('stamps arrival time using the injected clock', () async {
    final sync = FakeSync();
    final fixed = DateTime(2026, 5, 28, 21, 43);
    final store = ChatStore(sync: sync, now: () => fixed);

    sync.incoming(const ChatMessage(username: 'lin', text: 'hi'));
    await Future<void>.delayed(Duration.zero);

    expect(store.messages.single.timestamp, fixed);
    await store.dispose();
    await sync.dispose();
  });

  test('emits the updated list on its stream', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);
    final future = store.stream.first;

    sync.incoming(const ChatMessage(username: 'lin', text: 'hi'));

    final list = await future;
    expect(list.single.text, 'hi');
    await store.dispose();
    await sync.dispose();
  });

  test('send delegates to sync.sendChat', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);

    store.send('hello');

    expect(sync.sent, ['hello']);
    await store.dispose();
    await sync.dispose();
  });

  test('control messages are routed, not shown in history', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);
    final reaction = store.reactions.first;
    final typing = store.typing.first;

    sync.incoming(ChatMessage(username: 'lin', text: encodeReaction('🎉')));
    sync.incoming(ChatMessage(username: 'lin', text: encodeTyping(true)));
    sync.incoming(const ChatMessage(username: 'lin', text: 'real msg'));
    await Future<void>.delayed(Duration.zero);

    expect((await reaction).emoji, '🎉');
    expect((await reaction).username, 'lin');
    expect((await typing).isTyping, isTrue);
    // Only the real message reaches chat history.
    expect(store.messages.map((m) => m.text), ['real msg']);

    await store.dispose();
    await sync.dispose();
  });

  test('sendReaction / sendTyping emit encoded control messages', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);

    store.sendReaction('👍');
    store.sendTyping(isTyping: true);

    expect(sync.sent, [encodeReaction('👍'), encodeTyping(true)]);
    await store.dispose();
    await sync.dispose();
  });

  test('typing echoes exclude only the currently assigned self name', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync, initialUsername: 'me');
    final events = <TypingEvent>[];
    final subscription = store.typing.listen(events.add);
    sync.incoming(ChatMessage(username: 'me', text: encodeTyping(true)));
    sync.incoming(ChatMessage(username: 'friend', text: encodeTyping(true)));
    await Future<void>.delayed(Duration.zero);
    sync.connectedAs('me_');
    await Future<void>.delayed(Duration.zero);
    sync.incoming(ChatMessage(username: 'me_', text: encodeTyping(true)));
    sync.incoming(ChatMessage(username: 'me', text: encodeTyping(true)));
    sync.incoming(ChatMessage(username: 'friend', text: encodeTyping(false)));
    await Future<void>.delayed(Duration.zero);
    expect(events.map((event) => event.username), ['friend', 'me', 'friend']);
    expect(events.map((event) => event.isTyping), [true, true, false]);
    expect(store.messages, isEmpty);
    await subscription.cancel();
    await store.dispose();
    await sync.dispose();
  });

  test('leaving signal routes to leaving stream, not chat history', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);
    final leavingFuture = store.leaving.first;

    sync.incoming(ChatMessage(username: 'lin', text: encodeLeaving()));
    sync.incoming(const ChatMessage(username: 'bob', text: 'real msg'));
    await Future<void>.delayed(Duration.zero);

    expect(await leavingFuture, 'lin');
    // Leaving signal must not appear in history.
    expect(store.messages.map((m) => m.text), ['real msg']);

    await store.dispose();
    await sync.dispose();
  });

  test(
    'addSystem inserts a local system line, not sent over the wire',
    () async {
      final sync = FakeSync();
      final store = ChatStore(sync: sync);

      store.addSystem('lin joined the room');
      await Future<void>.delayed(Duration.zero);

      expect(sync.sent, isEmpty); // never transmitted
      final msg = store.messages.single;
      expect(msg.system, isTrue);
      expect(msg.text, 'lin joined the room');
      expect(msg.timestamp, isNotNull);

      await store.dispose();
      await sync.dispose();
    },
  );

  test('stamps isMine on messages from our assigned username', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);

    sync.connectedAs('meow');
    sync.incoming(const ChatMessage(username: 'meow', text: 'mine'));
    sync.incoming(const ChatMessage(username: 'lin', text: 'theirs'));
    await Future<void>.delayed(Duration.zero);

    final byText = {for (final m in store.messages) m.text: m.isMine};
    expect(byText['mine'], isTrue);
    expect(byText['theirs'], isFalse);
    await store.dispose();
    await sync.dispose();
  });

  test(
    'initialUsername stamps isMine without a later connection emit',
    () async {
      final sync = FakeSync();
      final store = ChatStore(sync: sync, initialUsername: 'meow');

      sync.incoming(const ChatMessage(username: 'meow', text: 'mine'));
      sync.incoming(const ChatMessage(username: 'lin', text: 'theirs'));
      await Future<void>.delayed(Duration.zero);

      final byText = {for (final m in store.messages) m.text: m.isMine};
      expect(byText['mine'], isTrue);
      expect(byText['theirs'], isFalse);
      await store.dispose();
      await sync.dispose();
    },
  );

  test('a message arriving before any connection state is not mine', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);

    sync.incoming(const ChatMessage(username: 'meow', text: 'early'));
    await Future<void>.delayed(Duration.zero);

    expect(store.messages.single.isMine, isFalse);
    await store.dispose();
    await sync.dispose();
  });

  test('caps retained history, dropping the oldest lines', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);

    for (var i = 0; i < ChatStore.maxRetained + 10; i++) {
      sync.incoming(ChatMessage(username: 'lin', text: 'm$i'));
    }
    await Future<void>.delayed(Duration.zero);

    expect(store.messages.length, ChatStore.maxRetained);
    expect(store.messages.first.text, 'm10');
    expect(store.messages.last.text, 'm${ChatStore.maxRetained + 9}');
    await store.dispose();
    await sync.dispose();
  });

  test('system lines count toward the history cap', () async {
    final sync = FakeSync();
    final store = ChatStore(sync: sync);

    for (var i = 0; i < ChatStore.maxRetained; i++) {
      sync.incoming(ChatMessage(username: 'lin', text: 'm$i'));
    }
    await Future<void>.delayed(Duration.zero);
    store.addSystem('lin joined the room');
    await Future<void>.delayed(Duration.zero);

    expect(store.messages.length, ChatStore.maxRetained);
    expect(store.messages.first.text, 'm1');
    expect(store.messages.last.text, 'lin joined the room');
    await store.dispose();
    await sync.dispose();
  });

  group('appendedMessages', () {
    const a = ChatMessage(username: 'lin', text: 'a');
    const b = ChatMessage(username: 'lin', text: 'b');
    const c = ChatMessage(username: 'lin', text: 'c');
    const d = ChatMessage(username: 'lin', text: 'd');

    test('pure append: everything past the old length', () {
      expect(appendedMessages(const [a, b], const [a, b, c, d]), [c, d]);
    });

    test('first snapshot: the whole list is new', () {
      expect(appendedMessages(const [], const [a, b]), [a, b]);
    });

    test('trimmed same-length list: anchors on the old last instance', () {
      // The retention cap drops 'a' as 'd' arrives — length stays equal, but
      // 'd' is still detected as new.
      expect(appendedMessages(const [a, b, c], const [b, c, d]), [d]);
    });

    test('unchanged list: nothing new', () {
      expect(appendedMessages(const [a, b], const [a, b]), isEmpty);
    });

    test('wholesale replacement: nothing provably new', () {
      expect(appendedMessages(const [a, b], const [c, d]), isEmpty);
    });

    test(
      'append with a coincident front-trim: longer list is not a prefix',
      () {
        // Two lines arrive while the list sits at the retention cap: both are
        // appended and the oldest is trimmed in the same coalesced update, so
        // `current` is longer than `old` yet no longer starts with it. A bare
        // length fast path (`current.sublist(old.length)`) drops the first new
        // line ('f'); both must be reported.
        const e = ChatMessage(username: 'lin', text: 'e');
        const f = ChatMessage(username: 'lin', text: 'f');
        const g = ChatMessage(username: 'lin', text: 'g');
        expect(
          appendedMessages(const [a, b, c, d, e], const [b, c, d, e, f, g]),
          [f, g],
        );
      },
    );
  });

  test('tracks ownership across a reconnect rename (collision dedupe)', () async {
    // The server can hand us a different name on reconnect ("meow" -> "meow_").
    // Ownership is stamped at receipt against our *current* name, so a message
    // received while we were "meow" stays ours, and our later echoes arrive
    // under "meow_". This is the #40/#77 flip the fix targets.
    final sync = FakeSync();
    final store = ChatStore(sync: sync);

    sync.connectedAs('meow');
    sync.incoming(const ChatMessage(username: 'meow', text: 'before'));
    sync.connectedAs('meow_');
    sync.incoming(const ChatMessage(username: 'meow_', text: 'after'));
    // A peer has since claimed the name the server freed when it renamed us.
    // Their messages under the old name must NOT count as ours.
    sync.incoming(const ChatMessage(username: 'meow', text: 'peer-took-old'));
    sync.incoming(const ChatMessage(username: 'lin', text: 'peer'));
    await Future<void>.delayed(Duration.zero);

    final byText = {for (final m in store.messages) m.text: m.isMine};
    expect(byText['before'], isTrue); // stamped while we were "meow"
    expect(byText['after'], isTrue); // our echo under the new name
    expect(byText['peer-took-old'], isFalse); // freed name, now a peer's
    expect(byText['peer'], isFalse);
    await store.dispose();
    await sync.dispose();
  });
}
