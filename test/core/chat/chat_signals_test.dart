import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/chat/chat_signals.dart';

void main() {
  group('parseChatControl', () {
    test('ordinary chat is not a control message', () {
      expect(parseChatControl('hello there'), isNull);
      expect(parseChatControl('react:👍 without sentinel'), isNull);
    });

    test('round-trips a reaction', () {
      final encoded = encodeReaction('🎉');
      final signal = parseChatControl(encoded);
      expect(signal, isA<ReactionSignal>());
      expect((signal! as ReactionSignal).emoji, '🎉');
    });

    test('round-trips typing on/off', () {
      expect(
        (parseChatControl(encodeTyping(true))! as TypingSignal).isTyping,
        isTrue,
      );
      expect(
        (parseChatControl(encodeTyping(false))! as TypingSignal).isTyping,
        isFalse,
      );
    });

    test('reaction with empty payload is ignored', () {
      expect(parseChatControl('${chatControlSentinel}react:'), isNull);
    });

    test('unknown control type is ignored', () {
      expect(parseChatControl('${chatControlSentinel}bogus:1'), isNull);
    });

    test('sentinel starts with a non-typable control char', () {
      expect(chatControlSentinel.codeUnitAt(0), 0x01);
    });

    test('round-trips leaving signal', () {
      final encoded = encodeLeaving();
      final signal = parseChatControl(encoded);
      expect(signal, isA<LeavingSignal>());
    });

    test('leaving signal without payload parses correctly', () {
      final signal = parseChatControl('${chatControlSentinel}leaving');
      expect(signal, isA<LeavingSignal>());
    });
  });
}
