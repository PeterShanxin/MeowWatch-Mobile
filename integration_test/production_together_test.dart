import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/app/app_services.dart';
import 'package:meowwatch_mobile/core/billing/file_hosting_quota_store.dart';
import 'package:meowwatch_mobile/core/billing/hosting_access_policy.dart';
import 'package:meowwatch_mobile/core/billing/revenuecat_billing_service.dart';
import 'package:meowwatch_mobile/core/playback/local_mobile_target.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';
import 'package:meowwatch_mobile/main.dart';
import 'package:meowwatch_mobile/ui/chat/chat_panel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../tools/native_capture/native_screenshot.dart';
import '../tools/production_together/json_request.dart';
import 'support/native_invite_qr.dart';

const _role = String.fromEnvironment('TOGETHER_ROLE', defaultValue: 'host');
const _runId = String.fromEnvironment('TOGETHER_ROOM');
const _server = String.fromEnvironment(
  'SYNCPLAY_SERVER',
  defaultValue: 'syncplay.pl',
);
const _port = int.fromEnvironment('SYNCPLAY_PORT', defaultValue: 8995);
const _videoUrl = String.fromEnvironment(
  'TOGETHER_VIDEO_URL',
  defaultValue:
      'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
);
const _coordinationUrl = String.fromEnvironment('TOGETHER_COORDINATION_URL');
const _pollInterval = Duration(milliseconds: 150);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'production UI keeps two real Android players together',
    (tester) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason:
            'This acceptance slice requires two independent Android runtimes.',
      );
      expect(['host', 'guest'], contains(_role));
      expect(
        _runId,
        isNotEmpty,
        reason:
            'Both APKs must be compiled with the same unique TOGETHER_ROOM run ID.',
      );
      expect(_port, inInclusiveRange(1, 65535));
      expect(
        RegExp(r'^[A-Za-z0-9._-]{1,80}$').hasMatch(_runId),
        isTrue,
        reason: 'TOGETHER_ROOM is also the filesystem-safe rendezvous run ID.',
      );
      expect(
        _coordinationUrl,
        isNotEmpty,
        reason:
            'Pass a short-lived TOGETHER_COORDINATION_URL reachable by both Androids.',
      );

      final isHost = _role == 'host';
      final peerRole = isHost ? 'guest' : 'host';
      final name = isHost ? 'Production Host' : 'Production Guest';
      final peerName = isHost ? 'Production Guest' : 'Production Host';
      final screenshots = <String>[];
      final verified = <String>[];
      final observations = <Map<String, Object?>>[];

      final support = await getApplicationSupportDirectory();
      final repositoryFile = File(
        '${support.path}/production-together-$_runId-$_role.json',
      );
      final quotaFile = File(
        '${support.path}/production-together-quota-$_runId-$_role.json',
      );
      for (final file in [repositoryFile, quotaFile]) {
        if (await file.exists()) await file.delete();
      }
      final repository = AppRepository(repositoryFile);
      final billing = RevenueCatBillingService(apiKey: revenueCatPublicKey);
      final phone = LocalMobileTarget();
      final hosting = LocalHostingAccessPolicy(
        store: FileHostingQuotaStore(quotaFile),
        isPlus: () => billing.isPlus,
      );
      final app = AppController(
        repository: repository,
        billing: billing,
        hosting: hosting,
        phone: phone,
      );
      addTearDown(app.close);

      final nativeScreenshots = NativeScreenshots(binding);
      await tester.pumpWidget(MainApp(controller: app));
      await _completeOnboarding(tester, name);
      verified.addAll([
        'production_app_bootstrap',
        'display_name_entered_via_ui',
      ]);

      if (isHost) {
        await _tap(
          tester,
          find.byKey(const Key('start-room-button')),
          'production Start a room button',
        );
        verified.add('host_started_room_via_ui');
        await _waitForCondition(
          tester,
          () => app.inPlayer && app.isConnected && app.invite != null,
          app,
          'production-created room invitation',
          timeout: const Duration(seconds: 90),
        );
        final generatedInvite = app.invite;
        expect(generatedInvite, isNotNull);
        await _publishInvite(generatedInvite!.toString());
        verified.add('production_invite_published_to_test_rendezvous');
      } else {
        final invite = await _waitForInvite();
        final decodedInvite = await decodeGeneratedInviteQr(invite);
        expect(decodedInvite, invite);
        verified.add('generated_invite_qr_decoded_by_android_mlkit');
        await _joinThroughUi(tester, decodedInvite);
        verified.add('guest_joined_room_via_ui');
      }

      await _waitForCondition(
        tester,
        () => app.inPlayer && app.isConnected && app.room != null,
        app,
        'secure room connection',
        timeout: const Duration(seconds: 90),
      );
      await _waitForCondition(
        tester,
        () => app.peers.contains(peerName),
        app,
        'peer presence',
        timeout: const Duration(seconds: 90),
      );
      // The tablet video occupies most of the details viewport. Reveal the
      // real roster with a gesture instead of waiting for an offscreen lazy
      // ListView child to be built. Its first Scrollable owns the list viewport;
      // later descendants include the empty video stage's nested scroll view.
      final roomDetails = find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      final peerLabel = find.text(peerName);
      for (
        var scrolls = 0;
        peerLabel.evaluate().isEmpty && scrolls < 8;
        scrolls++
      ) {
        final bounds = tester.getRect(roomDetails);
        // The list's padding is outside the independently scrolling stage.
        await tester.dragFrom(
          Offset(bounds.left + 8, bounds.center.dy),
          const Offset(0, -250),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.ensureVisible(peerLabel);
      await _waitFor(
        tester,
        peerLabel.hitTestable(),
        'visible peer name in production UI',
      );
      await _capture(nativeScreenshots, tester, screenshots, 'room-ready');
      await tester.drag(roomDetails, const Offset(0, 800));
      await tester.pump(const Duration(milliseconds: 250));
      _observe(observations, app, 'room-ready');
      verified.addAll(['starttls_room_connected', 'peer_presence_rendered']);

      await _signalCheckpoint('room-ready');
      await _waitForCheckpoint(tester, peerRole, 'room-ready');

      if (isHost) {
        await _loadVideoThroughUi(tester, app);
        await _signalCheckpoint('video-ready');
        await _waitForCheckpoint(tester, 'guest', 'video-ready');
      } else {
        await _waitForCheckpoint(tester, 'host', 'video-ready');
        await _loadVideoThroughUi(tester, app);
        await _signalCheckpoint('video-ready');
      }
      await _waitForCondition(
        tester,
        () => app.peerFiles.isNotEmpty,
        app,
        'peer media presence',
        timeout: const Duration(seconds: 45),
      );
      expect(find.byType(VideoPlayer), findsOneWidget);
      await _capture(nativeScreenshots, tester, screenshots, 'video-ready');
      _observe(observations, app, 'video-ready');
      verified.addAll([
        'direct_video_loaded_via_ui',
        'android_video_texture_rendered',
        'peer_media_received',
      ]);

      int? hostPausedPosition;
      int? peerPausePosition;
      int? hostSeekPosition;
      int? peerSeekPosition;
      int? guestPausedPosition;
      int? hostObservedGuestPause;

      if (isHost) {
        final beforePlay = app.target.snapshot.position.inMilliseconds;
        await _tapPlayControl(tester, play: true);
        await _waitForCondition(
          tester,
          () =>
              app.target.snapshot.playing &&
              app.target.snapshot.position.inMilliseconds >= beforePlay + 400,
          app,
          'host playback to advance',
          timeout: const Duration(seconds: 20),
        );
        await _capture(
          nativeScreenshots,
          tester,
          screenshots,
          'host-controlling-play',
        );
        await _signalCheckpoint('host-playing');
        await _waitForCheckpoint(tester, 'guest', 'guest-saw-play');

        await _tapPlayControl(tester, play: false);
        hostPausedPosition = await _waitForSettledPause(
          tester,
          app,
          observations,
          'host-paused',
        );
        await _signalCheckpoint('host-paused', value: '$hostPausedPosition');
        await _waitForCheckpoint(tester, 'guest', 'guest-saw-pause');
        await _capture(
          nativeScreenshots,
          tester,
          screenshots,
          'host-paused-together',
        );

        hostSeekPosition = await _seekThroughUi(tester, app, 0.58);
        await _signalCheckpoint('host-sought', value: '$hostSeekPosition');
        await _waitForCheckpoint(tester, 'guest', 'guest-saw-seek');
        await _capture(
          nativeScreenshots,
          tester,
          screenshots,
          'host-sought-together',
        );

        await _signalCheckpoint('guest-control');
        await _waitForCheckpoint(tester, 'guest', 'guest-playing');
        await _waitForCondition(
          tester,
          () => app.target.snapshot.playing,
          app,
          'guest play reflected on host',
        );
        await _signalCheckpoint('host-saw-guest-play');
        final guestPauseValue = await _waitForCheckpoint(
          tester,
          'guest',
          'guest-paused',
        );
        guestPausedPosition = _checkpointPosition(
          guestPauseValue,
          'guest-paused',
        );
        await _waitForCondition(
          tester,
          () =>
              !app.target.snapshot.playing &&
              (app.target.snapshot.position.inMilliseconds -
                          guestPausedPosition!)
                      .abs() <
                  800,
          app,
          'guest pause convergence on host '
          '(expectedPositionMs=$guestPausedPosition)',
        );
        hostObservedGuestPause = app.target.snapshot.position.inMilliseconds;
        await _signalCheckpoint('host-saw-guest-pause');
      } else {
        await _waitForCheckpoint(tester, 'host', 'host-playing');
        final beforeObservation = app.target.snapshot.position.inMilliseconds;
        await _waitForCondition(
          tester,
          () =>
              app.target.snapshot.playing &&
              app.target.snapshot.position.inMilliseconds >=
                  beforeObservation + 300,
          app,
          'host play reflected on guest',
          timeout: const Duration(seconds: 20),
        );
        await _capture(
          nativeScreenshots,
          tester,
          screenshots,
          'guest-saw-host-play',
        );
        await _signalCheckpoint('guest-saw-play');

        final pauseValue = await _waitForCheckpoint(
          tester,
          'host',
          'host-paused',
        );
        hostPausedPosition = _checkpointPosition(pauseValue, 'host-paused');
        await _waitForCondition(
          tester,
          () =>
              !app.target.snapshot.playing &&
              (app.target.snapshot.position.inMilliseconds -
                          hostPausedPosition!)
                      .abs() <
                  800,
          app,
          'host pause convergence on guest '
          '(expectedPositionMs=$hostPausedPosition)',
        );
        peerPausePosition = app.target.snapshot.position.inMilliseconds;
        await _signalCheckpoint('guest-saw-pause');
        await _capture(
          nativeScreenshots,
          tester,
          screenshots,
          'guest-paused-together',
        );

        final seekValue = await _waitForCheckpoint(
          tester,
          'host',
          'host-sought',
        );
        hostSeekPosition = _checkpointPosition(seekValue, 'host-sought');
        await _waitForCondition(
          tester,
          () =>
              !app.target.snapshot.playing &&
              (app.target.snapshot.position.inMilliseconds - hostSeekPosition!)
                      .abs() <
                  900,
          app,
          'host seek convergence on guest',
        );
        peerSeekPosition = app.target.snapshot.position.inMilliseconds;
        await _signalCheckpoint('guest-saw-seek');
        await _capture(
          nativeScreenshots,
          tester,
          screenshots,
          'guest-sought-together',
        );

        await _waitForCheckpoint(tester, 'host', 'guest-control');
        final beforePlay = app.target.snapshot.position.inMilliseconds;
        await _tapPlayControl(tester, play: true);
        await _waitForCondition(
          tester,
          () =>
              app.target.snapshot.playing &&
              app.target.snapshot.position.inMilliseconds >= beforePlay + 300,
          app,
          'guest playback to advance',
          timeout: const Duration(seconds: 20),
        );
        await _signalCheckpoint('guest-playing');
        await _waitForCheckpoint(tester, 'host', 'host-saw-guest-play');
        await _tapPlayControl(tester, play: false);
        guestPausedPosition = await _waitForSettledPause(
          tester,
          app,
          observations,
          'guest-paused',
        );
        await _signalCheckpoint('guest-paused', value: '$guestPausedPosition');
        await _waitForCheckpoint(tester, 'host', 'host-saw-guest-pause');
      }
      await _capture(
        nativeScreenshots,
        tester,
        screenshots,
        'two-way-sync-complete',
      );
      _observe(observations, app, 'two-way-sync-complete');
      verified.addAll([
        'host_play_synchronized',
        'host_pause_synchronized',
        'host_seek_synchronized',
        'guest_play_synchronized',
        'guest_pause_synchronized',
      ]);

      const guestChat = 'Ready for movie night, Host! 🍿';
      const hostChat = 'Ready here too. Press play when you are comfy.';
      if (isHost) {
        await _waitForRemoteMessage(tester, app, guestChat);
        await _openChat(tester);
        await _expectChatMessageVisible(tester, guestChat);
        expect(find.text(peerName), findsWidgets);
        await _sendChatThroughUi(tester, app, hostChat, closeAfter: false);
        await _capture(nativeScreenshots, tester, screenshots, 'chat-visible');
        await _closeChatIfNeeded(tester);
      } else {
        await _sendChatThroughUi(tester, app, guestChat);
        await _waitForRemoteMessage(tester, app, hostChat);
        await _openChat(tester);
        await _expectChatMessageVisible(tester, hostChat);
        expect(find.text(peerName), findsWidgets);
        await _capture(nativeScreenshots, tester, screenshots, 'chat-visible');
        await _closeChatIfNeeded(tester);
      }
      verified.add('chat_sent_and_rendered_via_production_ui');

      if (isHost) {
        await _signalCheckpoint('send-heart');
        await _waitForCondition(
          tester,
          () =>
              app.reaction?.emoji == '❤️' && app.reaction?.username == peerName,
          app,
          'remote heart reaction',
          timeout: const Duration(seconds: 30),
        );
        await _waitFor(
          tester,
          find.text('❤️'),
          'reaction overlay in production player',
        );
        await _capture(
          nativeScreenshots,
          tester,
          screenshots,
          'reaction-visible',
        );
        await _signalCheckpoint('heart-seen');
      } else {
        await _waitForCheckpoint(tester, 'host', 'send-heart');
        await _sendReactionThroughUi(tester, '❤️');
        await _waitForCheckpoint(tester, 'host', 'heart-seen');
      }
      verified.add('reaction_sent_and_rendered_via_production_ui');
      _observe(observations, app, 'social-complete');

      // Both devices use their real, initially empty quota stores. The joining
      // device still has its free host available for the later movie night.
      expect(
        billing.isPlus,
        isFalse,
        reason: 'This journey verifies free quota.',
      );
      final originalRoom = app.room!;
      final originalInvite = app.invite.toString();
      final originalAllowance = isHost ? 0 : 1;
      expect(await hosting.remainingFreeHostsToday(), originalAllowance);
      final originalQuota = await _quotaContents(quotaFile);
      if (isHost) {
        final ledger = jsonDecode(originalQuota!) as Map<String, dynamic>;
        final sessions = ledger['sessions'] as Map<String, dynamic>;
        expect(sessions.keys, [originalRoom.id]);
        expect(sessions[originalRoom.id]['usedFreeHost'], isTrue);
      } else {
        expect(
          originalQuota,
          isNull,
          reason: 'Joining must not consume a host.',
        );
      }

      final sharedUri = Uri.parse(_videoUrl).replace(
        queryParameters: {
          ...Uri.parse(_videoUrl).queryParameters,
          'shared': 'movie-night',
        },
      );
      expect(sharedUri.toString().length, lessThanOrEqualTo(150));
      if (isHost) {
        final previousController = phone.controller;
        await _waitForRemoteMessage(tester, app, sharedUri.toString());
        expect(app.target.snapshot.media!.uri, Uri.parse(_videoUrl));
        expect(identical(phone.controller, previousController), isTrue);
        await _openChat(tester);
        await _tap(tester, find.text('Watch this too'), 'review shared video');
        await _waitFor(
          tester,
          find.text('Watch this too?'),
          'shared link review',
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is SelectableText && widget.data == sharedUri.toString(),
          ),
          findsOneWidget,
        );
        expect(app.target.snapshot.media!.uri, Uri.parse(_videoUrl));
        expect(identical(phone.controller, previousController), isTrue);
        await _capture(
          nativeScreenshots,
          tester,
          screenshots,
          'shared-link-review',
        );
        await _tap(
          tester,
          find.text('Load video'),
          'confirm trusted shared video',
        );
        await _waitForNativeVideo(tester, app, sharedUri);
        expect(identical(phone.controller, previousController), isFalse);
        await _closeChatIfNeeded(tester);
        await _signalCheckpoint('shared-link-loaded');
        verified.addAll([
          'peer_link_waited_for_explicit_confirmation',
          'peer_link_created_real_native_decoder',
        ]);
      } else {
        await _sendChatThroughUi(tester, app, sharedUri.toString());
        await _waitForCheckpoint(tester, 'host', 'shared-link-loaded');
        verified.add('playable_video_link_sent_via_production_chat');
      }
      await _verifyTogetherPlaybackCycle(
        tester,
        app,
        observations,
        stage: 'shared-link',
        controllingRole: 'host',
      );
      await _expectRoomAndQuotaUnchanged(
        app,
        hosting,
        quotaFile,
        originalRoom,
        originalQuota,
        originalAllowance,
        observations,
        'shared-link',
      );
      await _capture(
        nativeScreenshots,
        tester,
        screenshots,
        'shared-link-playing-verified',
      );
      verified.add('shared_video_playback_kept_room_and_host_quota');

      // The owned fixture server returns 404 for this unique, nonexistent MP4.
      // A real decoder failure must be recoverable without leaving the room.
      final missingUri = Uri.parse(_videoUrl).resolve('missing-$_runId.mp4');
      await _chooseVideoUrlThroughUi(tester, missingUri.toString());
      const mediaError =
          'Could not open this video. Check your connection and use a direct video link, not a webpage.';
      await _waitForCondition(
        tester,
        () =>
            app.target.snapshot.error == mediaError &&
            !app.target.snapshot.ready,
        app,
        'native missing-video failure',
        timeout: const Duration(seconds: 45),
      );
      await _waitFor(tester, find.text(mediaError), 'readable media error');
      await tester.ensureVisible(find.text(mediaError).first);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(mediaError).hitTestable(), findsWidgets);
      await _waitFor(
        tester,
        find.text('Choose another video'),
        'media recovery action',
      );
      expect(app.target.snapshot.playing, isFalse);
      await _expectRoomAndQuotaUnchanged(
        app,
        hosting,
        quotaFile,
        originalRoom,
        originalQuota,
        originalAllowance,
        observations,
        'media-error',
      );
      await _capture(
        nativeScreenshots,
        tester,
        screenshots,
        'readable-media-error',
      );
      await _signalCheckpoint('media-error-shown');
      await _waitForCheckpoint(tester, peerRole, 'media-error-shown');
      await _loadVideoThroughUi(
        tester,
        app,
        picker: find.text('Choose another video'),
      );
      expect(app.target.snapshot.error, isNull);
      await _signalCheckpoint('media-recovered');
      await _waitForCheckpoint(tester, peerRole, 'media-recovered');
      await _verifyTogetherPlaybackCycle(
        tester,
        app,
        observations,
        stage: 'media-recovery',
        controllingRole: 'host',
      );
      await _expectRoomAndQuotaUnchanged(
        app,
        hosting,
        quotaFile,
        originalRoom,
        originalQuota,
        originalAllowance,
        observations,
        'media-recovery',
      );
      await _capture(nativeScreenshots, tester, screenshots, 'media-recovered');
      verified.addAll([
        'failed_media_rendered_readable_error',
        'choose_another_video_restored_native_playback',
        'recovered_media_synchronized_in_same_room_without_new_host_charge',
      ]);

      // Resume reuses the original charged host ID while the guest remains
      // connected. Neither a new room nor a second allowance is needed.
      if (isHost) {
        await _leaveToHome(tester, app);
        final entry = repository.history.firstWhere(
          (entry) =>
              entry.room?.id == originalRoom.id &&
              entry.media.uri == Uri.parse(_videoUrl),
        );
        expect(entry.position, greaterThan(Duration.zero));
        await _tap(
          tester,
          find.byKey(ValueKey('resume-${entry.key}')),
          'Continue Watching for the existing room',
        );
        await _waitForRoomAndVideo(tester, app, peerName, Uri.parse(_videoUrl));
        expect(
          (app.target.snapshot.position - entry.position).inMilliseconds.abs(),
          lessThan(800),
          reason: 'Resume must restore the saved native position.',
        );
        await _signalCheckpoint('history-resumed');
      } else {
        await _waitForCheckpoint(tester, 'host', 'history-resumed');
      }
      await _verifyTogetherPlaybackCycle(
        tester,
        app,
        observations,
        stage: 'history-resume',
        controllingRole: 'host',
      );
      await _expectRoomAndQuotaUnchanged(
        app,
        hosting,
        quotaFile,
        originalRoom,
        originalQuota,
        originalAllowance,
        observations,
        'history-resume',
      );
      await _capture(nativeScreenshots, tester, screenshots, 'history-resumed');
      verified.add(
        'room_history_resume_reused_session_endpoint_and_host_quota',
      );

      // Swap hosting roles for a genuinely new movie night. The original guest
      // uses its own remaining free host; no entitlement or clock is modified.
      await _leaveToHome(tester, app);
      await _signalCheckpoint('watch-again-home');
      await _waitForCheckpoint(tester, peerRole, 'watch-again-home');
      if (!isHost) {
        await _tap(
          tester,
          find.byKey(ValueKey('watch-again-${originalRoom.contextKey}')),
          'Recent rooms Watch together again',
        );
        await _waitForCondition(
          tester,
          () => app.isConnected && app.room != null && app.invite != null,
          app,
          'new room from Recent rooms',
          timeout: const Duration(seconds: 45),
        );
        expect(app.room!.id, isNot(originalRoom.id));
        expect(app.room!.config.room, isNot(originalRoom.config.room));
        expect(app.room!.isHost, isTrue);
        expect(app.invite.toString(), isNot(originalInvite));
        await _waitForNativeVideo(tester, app, Uri.parse(_videoUrl));
        expect(app.target.snapshot.playing, isFalse);
        expect(await hosting.remainingFreeHostsToday(), 1);
        expect(await _quotaContents(quotaFile), originalQuota);
        final newInvite = app.invite.toString();
        expect(newInvite.length, lessThanOrEqualTo(256));
        await _signalCheckpoint('watch-again-invite', value: newInvite);
      } else {
        final newInvite = await _waitForCheckpoint(
          tester,
          'guest',
          'watch-again-invite',
        );
        expect(newInvite, isNotNull);
        expect(newInvite, isNot(originalInvite));
        await _joinThroughUi(tester, await decodeGeneratedInviteQr(newInvite!));
        await _waitForCondition(
          tester,
          () => app.isConnected && app.room != null,
          app,
          'join the new movie night',
          timeout: const Duration(seconds: 45),
        );
        expect(app.room!.id, isNot(originalRoom.id));
        expect(app.room!.config.room, isNot(originalRoom.config.room));
        expect(app.room!.isHost, isFalse);
        await _loadVideoThroughUi(tester, app);
      }
      await _waitForRoomAndVideo(tester, app, peerName, Uri.parse(_videoUrl));
      final nextRoom = app.room!;
      expect(await hosting.remainingFreeHostsToday(), originalAllowance);
      expect(await _quotaContents(quotaFile), originalQuota);
      await _signalCheckpoint('watch-again-ready');
      await _waitForCheckpoint(tester, peerRole, 'watch-again-ready');
      await _verifyTogetherPlaybackCycle(
        tester,
        app,
        observations,
        stage: 'watch-again',
        controllingRole: 'guest',
      );
      expect(await hosting.remainingFreeHostsToday(), 0);
      expect(await hosting.canHostNow(), isFalse);
      if (isHost) {
        expect(
          await _quotaContents(quotaFile),
          originalQuota,
          reason:
              'Joining the new night must not charge the original host again.',
        );
        expect(await hosting.canHostNow(sessionId: originalRoom.id), isTrue);
      } else {
        final ledger =
            jsonDecode((await _quotaContents(quotaFile))!)
                as Map<String, dynamic>;
        final sessions = ledger['sessions'] as Map<String, dynamic>;
        expect(sessions.keys, [nextRoom.id]);
        expect(sessions[nextRoom.id]['usedFreeHost'], isTrue);
        expect(await hosting.canHostNow(sessionId: nextRoom.id), isTrue);
      }
      observations.add({
        'stage': 'watch-again-quota',
        'originalRoomId': originalRoom.id,
        'newRoomId': nextRoom.id,
        'newRoomIsHost': nextRoom.isHost,
        'remainingFreeHostsToday': 0,
        'atUtc': DateTime.now().toUtc().toIso8601String(),
      });
      await _capture(nativeScreenshots, tester, screenshots, 'new-movie-night');
      verified.addAll([
        'recent_rooms_created_fresh_room_and_invite',
        'peer_rejoined_new_movie_night_via_qr_decode_and_join_ui',
        'new_host_charged_once_at_playback_original_host_not_charged_for_join',
      ]);

      await _signalCheckpoint('complete');
      await _waitForCheckpoint(tester, peerRole, 'complete');

      final view = tester.view;
      final logicalSize = view.physicalSize / view.devicePixelRatio;
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['productionTogether'] = <String, Object?>{
        'result': 'passed',
        'role': _role,
        'entryRoute': isHost ? 'start-room-button' : 'join-room-sheet',
        'coordinationRunId': _runId,
        'initialRoom': <String, Object>{
          'id': originalRoom.id,
          'room': originalRoom.config.room,
          'server': '${originalRoom.config.server}:${originalRoom.config.port}',
          'isHost': originalRoom.isHost,
        },
        'finalRoomId': app.room!.id,
        'room': app.room!.config.room,
        'server': '${app.room!.config.server}:${app.room!.config.port}',
        'requestedServer': '$_server:$_port',
        'videoUrl': _videoUrl,
        'platform': Platform.operatingSystem,
        'operatingSystemVersion': Platform.operatingSystemVersion,
        'viewport': <String, Object>{
          'physicalWidth': view.physicalSize.width.round(),
          'physicalHeight': view.physicalSize.height.round(),
          'devicePixelRatio': view.devicePixelRatio,
          'logicalWidth': logicalSize.width,
          'logicalHeight': logicalSize.height,
        },
        'screenshots': screenshots,
        'verifiedSteps': verified,
        'observations': observations,
        'convergence': <String, Object?>{
          'hostPausedPositionMs': hostPausedPosition,
          'peerPausePositionMs': peerPausePosition,
          'hostPauseDeltaMs': peerPausePosition == null
              ? null
              : (hostPausedPosition - peerPausePosition).abs(),
          'hostSeekPositionMs': hostSeekPosition,
          'peerSeekPositionMs': peerSeekPosition,
          'hostSeekDeltaMs': peerSeekPosition == null
              ? null
              : (hostSeekPosition - peerSeekPosition).abs(),
          'guestPausedPositionMs': guestPausedPosition,
          'hostObservedGuestPauseMs': hostObservedGuestPause,
          'guestPauseDeltaMs': hostObservedGuestPause == null
              ? null
              : (guestPausedPosition - hostObservedGuestPause).abs(),
        },
        'completedAtUtc': DateTime.now().toUtc().toIso8601String(),
      };

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
      await app.close();
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

/// The runner owns one expiring invite plus bounded role checkpoints. Neither
/// resource participates in production room or playback behavior.
Uri _fixtureUri(String resource, [Map<String, String> query = const {}]) {
  final base = Uri.tryParse(_coordinationUrl);
  if (base == null ||
      !base.hasAuthority ||
      !const {'http', 'https'}.contains(base.scheme) ||
      !base.path.endsWith('/invite')) {
    throw TestFailure(
      'TOGETHER_COORDINATION_URL must be an HTTP(S) /invite fixture endpoint.',
    );
  }
  return base.replace(
    path:
        '${base.path.substring(0, base.path.length - 'invite'.length)}$resource',
    queryParameters: {...base.queryParameters, 'run': _runId, ...query},
  );
}

Future<void> _publishInvite(String invite) async {
  final endpoint = _fixtureUri('invite');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  final stopwatch = Stopwatch()..start();
  Object? lastError;
  try {
    while (stopwatch.elapsed < const Duration(seconds: 30)) {
      try {
        final request = await client.putUrl(endpoint);
        writeFixtureJson(request, <String, Object?>{
          'runId': _runId,
          'invite': invite,
          'publishedAtUtc': DateTime.now().toUtc().toIso8601String(),
        });
        final response = await request.close().timeout(
          const Duration(seconds: 5),
        );
        final status = response.statusCode;
        await response.drain<void>().timeout(const Duration(seconds: 5));
        if (status >= 200 && status < 300) return;
        lastError = HttpException('fixture returned HTTP $status');
      } catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  } finally {
    client.close(force: true);
  }
  throw TestFailure(
    'host could not publish its generated invite to the test rendezvous: '
    '${lastError.runtimeType}',
  );
}

Future<String> _waitForInvite() async {
  final endpoint = _fixtureUri('invite');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  final stopwatch = Stopwatch()..start();
  Object? lastError;
  try {
    while (stopwatch.elapsed < const Duration(seconds: 90)) {
      try {
        final request = await client.getUrl(endpoint);
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        final response = await request.close().timeout(
          const Duration(seconds: 5),
        );
        if (response.statusCode == HttpStatus.ok) {
          final body = await utf8.decoder
              .bind(response)
              .join()
              .timeout(const Duration(seconds: 5));
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic> &&
              decoded['runId'] == _runId &&
              decoded['invite'] is String) {
            final invite = decoded['invite'] as String;
            final uri = Uri.tryParse(invite);
            if (uri?.scheme == 'meowwatch' && uri?.host == 'join') {
              return invite;
            }
          }
          lastError = const FormatException(
            'fixture returned an invalid invitation payload',
          );
        } else {
          final status = response.statusCode;
          await response.drain<void>().timeout(const Duration(seconds: 5));
          if (status != HttpStatus.noContent && status != HttpStatus.notFound) {
            lastError = HttpException('fixture returned HTTP $status');
            if (status == HttpStatus.gone) break;
          }
        }
      } catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  } finally {
    client.close(force: true);
  }
  throw TestFailure(
    'guest did not receive the host-generated invite from the test rendezvous: '
    '${lastError.runtimeType}',
  );
}

Future<void> _signalCheckpoint(String checkpoint, {String? value}) async {
  final endpoint = _fixtureUri('checkpoint');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  final stopwatch = Stopwatch()..start();
  Object? lastError;
  var fatalResponse = false;
  try {
    while (stopwatch.elapsed < const Duration(seconds: 30)) {
      try {
        final request = await client.putUrl(endpoint);
        writeFixtureJson(request, <String, Object?>{
          'runId': _runId,
          'role': _role,
          'checkpoint': checkpoint,
          'value': value,
        });
        final response = await request.close().timeout(
          const Duration(seconds: 5),
        );
        final status = response.statusCode;
        await response.drain<void>().timeout(const Duration(seconds: 5));
        if (status >= 200 && status < 300) return;
        lastError = HttpException('fixture returned HTTP $status');
        fatalResponse = status >= 400 && status < 500;
      } catch (error) {
        lastError = error;
      }
      if (fatalResponse) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  } finally {
    client.close(force: true);
  }
  throw TestFailure(
    '$_role could not publish checkpoint $checkpoint: '
    '${lastError.runtimeType}',
  );
}

Future<String?> _waitForCheckpoint(
  WidgetTester tester,
  String role,
  String checkpoint,
) async {
  final endpoint = _fixtureUri('checkpoint', {
    'role': role,
    'checkpoint': checkpoint,
  });
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  final stopwatch = Stopwatch()..start();
  Object? lastError;
  var expired = false;
  try {
    while (stopwatch.elapsed < const Duration(seconds: 45)) {
      try {
        final request = await client.getUrl(endpoint);
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        final response = await request.close().timeout(
          const Duration(seconds: 5),
        );
        if (response.statusCode == HttpStatus.ok) {
          final body = await utf8.decoder
              .bind(response)
              .join()
              .timeout(const Duration(seconds: 5));
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic> &&
              decoded['runId'] == _runId &&
              decoded['role'] == role &&
              decoded['checkpoint'] == checkpoint &&
              (decoded['value'] == null || decoded['value'] is String)) {
            return decoded['value'] as String?;
          }
          lastError = const FormatException(
            'fixture returned an invalid checkpoint payload',
          );
        } else {
          final status = response.statusCode;
          await response.drain<void>().timeout(const Duration(seconds: 5));
          if (status != HttpStatus.notFound) {
            lastError = HttpException('fixture returned HTTP $status');
            expired = status == HttpStatus.gone;
          }
        }
      } catch (error) {
        lastError = error;
      }
      if (expired) break;
      await tester.pump(_pollInterval);
    }
  } finally {
    client.close(force: true);
  }
  throw TestFailure(
    '$_role did not receive $role checkpoint $checkpoint: '
    '${lastError.runtimeType}',
  );
}

Future<void> _completeOnboarding(WidgetTester tester, String name) async {
  final initial = await _waitForAny(
    tester,
    [
      find.byKey(const Key('display-name-field')),
      find.byKey(const Key('home-scroll-view')),
    ],
    'production app bootstrap',
    timeout: const Duration(seconds: 40),
  );
  if (initial.evaluate().first.widget.key == const Key('display-name-field')) {
    await tester.enterText(initial, name);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 200));
    await _tap(
      tester,
      find.byKey(const Key('onboarding-continue-button')),
      'continue production onboarding',
    );
  }
  await _waitFor(
    tester,
    find.byKey(const Key('home-scroll-view')),
    'production home',
    timeout: const Duration(seconds: 20),
  );
}

Future<void> _joinThroughUi(WidgetTester tester, String invite) async {
  await _tap(
    tester,
    find.byKey(const Key('join-room-button')),
    'production Join a room button',
  );
  final joinField = find.byKey(const Key('join-code-field'));
  await _waitFor(tester, joinField, 'production join sheet');
  await tester.enterText(joinField, invite);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 200));
  await _tap(
    tester,
    find.byKey(const Key('join-submit-button')),
    'production Join room submit button',
  );
}

Future<void> _loadVideoThroughUi(
  WidgetTester tester,
  AppController app, {
  Finder? picker,
}) async {
  await _chooseVideoUrlThroughUi(tester, _videoUrl, picker: picker);
  await _waitForNativeVideo(tester, app, Uri.parse(_videoUrl));
}

Future<void> _chooseVideoUrlThroughUi(
  WidgetTester tester,
  String url, {
  Finder? picker,
}) async {
  await _tap(
    tester,
    picker ?? find.widgetWithText(TextButton, 'Video'),
    'production media picker',
  );
  await _waitFor(
    tester,
    find.text('Choose what to watch'),
    'production media sheet',
  );
  final field = find.byType(TextField).hitTestable();
  await _waitFor(tester, field, 'direct video URL field');
  await tester.enterText(field.last, url);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 200));
  await _tap(tester, find.text('Use this link'), 'Use this link');
}

Future<void> _waitForNativeVideo(
  WidgetTester tester,
  AppController app,
  Uri uri,
) async {
  await _waitFor(
    tester,
    find.byType(VideoPlayer),
    'native Android video texture',
    timeout: const Duration(seconds: 70),
  );
  await _waitForCondition(
    tester,
    () =>
        app.target.snapshot.media?.uri == uri &&
        app.target.snapshot.ready &&
        app.target.snapshot.duration > const Duration(seconds: 10),
    app,
    'native playback metadata',
    timeout: const Duration(seconds: 30),
  );
}

Future<String?> _quotaContents(File file) async =>
    await file.exists() ? file.readAsString() : null;

Future<void> _expectRoomAndQuotaUnchanged(
  AppController app,
  LocalHostingAccessPolicy hosting,
  File quotaFile,
  RoomTicket originalRoom,
  String? originalQuota,
  int originalAllowance,
  List<Map<String, Object?>> observations,
  String stage,
) async {
  expect(
    app.isConnected,
    isTrue,
    reason: '$stage must keep the room connected.',
  );
  expect(app.peers, isNotEmpty);
  expect(app.room!.id, originalRoom.id);
  expect(app.room!.contextKey, originalRoom.contextKey);
  expect(app.room!.isHost, originalRoom.isHost);
  expect(app.needsPlus, isFalse);
  final remaining = await hosting.remainingFreeHostsToday();
  expect(remaining, originalAllowance);
  expect(
    await _quotaContents(quotaFile),
    originalQuota,
    reason: '$stage must not record another hosted session.',
  );
  observations.add({
    'stage': '$stage-quota',
    'roomId': app.room!.id,
    'roomEndpointUnchanged': true,
    'remainingFreeHostsToday': remaining,
    'quotaLedgerUnchanged': true,
    'atUtc': DateTime.now().toUtc().toIso8601String(),
  });
}

Future<void> _verifyTogetherPlaybackCycle(
  WidgetTester tester,
  AppController app,
  List<Map<String, Object?>> observations, {
  required String stage,
  required String controllingRole,
}) async {
  final otherRole = controllingRole == 'host' ? 'guest' : 'host';
  if (_role == controllingRole) {
    final beforePlay = app.target.snapshot.position.inMilliseconds;
    await _tapPlayControl(tester, play: true);
    await _waitForCondition(
      tester,
      () =>
          app.target.snapshot.playing &&
          app.target.snapshot.position.inMilliseconds >= beforePlay + 400,
      app,
      '$stage controlling player advancement',
      timeout: const Duration(seconds: 20),
    );
    await _signalCheckpoint('$stage-playing');
    await _waitForCheckpoint(tester, otherRole, '$stage-play-seen');
    await _tapPlayControl(tester, play: false);
    final paused = await _waitForSettledPause(
      tester,
      app,
      observations,
      '$stage-paused',
    );
    await _signalCheckpoint('$stage-paused', value: '$paused');
    await _waitForCheckpoint(tester, otherRole, '$stage-pause-seen');
  } else {
    await _waitForCheckpoint(tester, controllingRole, '$stage-playing');
    await _waitForCondition(
      tester,
      () => app.target.snapshot.playing,
      app,
      '$stage remote play',
      timeout: const Duration(seconds: 20),
    );
    final beforeProgress = app.target.snapshot.position.inMilliseconds;
    await _waitForCondition(
      tester,
      () =>
          app.target.snapshot.playing &&
          app.target.snapshot.position.inMilliseconds >= beforeProgress + 300,
      app,
      '$stage receiving player advancement',
      timeout: const Duration(seconds: 20),
    );
    await _signalCheckpoint('$stage-play-seen');
    final expected = _checkpointPosition(
      await _waitForCheckpoint(tester, controllingRole, '$stage-paused'),
      '$stage-paused',
    );
    await _waitForCondition(
      tester,
      () =>
          !app.target.snapshot.playing &&
          !app.playRequested &&
          (app.target.snapshot.position.inMilliseconds - expected).abs() < 800,
      app,
      '$stage pause convergence to ${expected}ms',
    );
    observations.add({
      'stage': '$stage-pause-convergence',
      'expectedPositionMs': expected,
      'actualPositionMs': app.target.snapshot.position.inMilliseconds,
      'deltaMs': (app.target.snapshot.position.inMilliseconds - expected).abs(),
      'atUtc': DateTime.now().toUtc().toIso8601String(),
    });
    await _signalCheckpoint('$stage-pause-seen');
  }
  _observe(observations, app, '$stage-playback-verified');
}

Future<void> _leaveToHome(WidgetTester tester, AppController app) async {
  await _closeChatIfNeeded(tester);
  await _tap(tester, find.byTooltip('Leave room'), 'leave room for home');
  await _waitForCondition(
    tester,
    () => !app.inPlayer && app.room == null,
    app,
    'home after leaving room',
  );
  await _waitFor(
    tester,
    find.byKey(const Key('home-scroll-view')),
    'production home',
  );
}

Future<void> _waitForRoomAndVideo(
  WidgetTester tester,
  AppController app,
  String peerName,
  Uri uri,
) async {
  await _waitForCondition(
    tester,
    () => app.isConnected && app.room != null && app.peers.contains(peerName),
    app,
    'both real participants in the room',
    timeout: const Duration(seconds: 45),
  );
  await _waitForNativeVideo(tester, app, uri);
}

Future<void> _tapPlayControl(WidgetTester tester, {required bool play}) async {
  final action = play ? 'Play' : 'Pause';
  final finder = await _waitForAny(tester, [
    find.byTooltip(action),
    find.byTooltip('$action together'),
  ], '$action control');
  await _tap(tester, finder, '$action through production controls');
}

Future<int> _waitForSettledPause(
  WidgetTester tester,
  AppController app,
  List<Map<String, Object?>> observations,
  String checkpoint,
) async {
  const positionToleranceMs = 350;
  const stableInterval = Duration(milliseconds: 800);
  const totalDeadline = Duration(seconds: 45);
  final totalClock = Stopwatch()..start();
  Stopwatch? stableClock;
  int? minimumPositionMs;
  int? maximumPositionMs;
  var stableSamples = 0;
  final recentSamples = <Map<String, Object?>>[];

  while (totalClock.elapsed < totalDeadline) {
    final snapshot = app.target.snapshot;
    final positionMs = snapshot.position.inMilliseconds;
    final playRequested = app.playRequested;
    final minimum = minimumPositionMs == null || positionMs < minimumPositionMs
        ? positionMs
        : minimumPositionMs;
    final maximum = maximumPositionMs == null || positionMs > maximumPositionMs
        ? positionMs
        : maximumPositionMs;
    final paused =
        snapshot.ready &&
        !snapshot.buffering &&
        !snapshot.playing &&
        !playRequested;
    recentSamples.add(<String, Object?>{
      'elapsedMs': totalClock.elapsed.inMilliseconds,
      'positionMs': positionMs,
      'playing': snapshot.playing,
      'playRequested': playRequested,
      'buffering': snapshot.buffering,
    });
    if (recentSamples.length > 16) recentSamples.removeAt(0);

    if (paused && maximum - minimum < positionToleranceMs) {
      stableClock ??= Stopwatch()..start();
      minimumPositionMs = minimum;
      maximumPositionMs = maximum;
      stableSamples++;
      // video_player clears isPlaying before native pause completes, and an
      // in-flight position query can arrive later. Publish the immutable test
      // checkpoint only after accepted pause intent and nine live observations.
      if (stableClock.elapsed >= stableInterval && stableSamples >= 9) {
        final observation = <String, Object?>{
          'stage': 'pause-checkpoint-settled',
          'checkpoint': checkpoint,
          'role': _role,
          'atUtc': DateTime.now().toUtc().toIso8601String(),
          'positionMs': positionMs,
          'settleElapsedMs': totalClock.elapsed.inMilliseconds,
          'stableElapsedMs': stableClock.elapsed.inMilliseconds,
          'stableSamples': stableSamples,
          'stablePositionRangeMs': maximum - minimum,
          'samples': List<Map<String, Object?>>.of(recentSamples),
        };
        observations.add(observation);
        debugPrint(
          'PRODUCTION_TOGETHER_PAUSE_SETTLED ${jsonEncode(observation)}',
        );
        return positionMs;
      }
    } else {
      stableClock?.stop();
      stableClock = null;
      minimumPositionMs = null;
      maximumPositionMs = null;
      stableSamples = 0;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  final snapshot = app.target.snapshot;
  throw TestFailure(
    '$_role pause checkpoint $checkpoint did not settle within '
    '${totalDeadline.inSeconds}s; playing=${snapshot.playing}, '
    'playRequested=${app.playRequested}, ready=${snapshot.ready}, '
    'buffering=${snapshot.buffering}, positionMs=${snapshot.position.inMilliseconds}, '
    'stableElapsedMs=${stableClock?.elapsed.inMilliseconds ?? 0}, '
    'stableSamples=$stableSamples, samples=${jsonEncode(recentSamples)}',
  );
}

Future<int> _seekThroughUi(
  WidgetTester tester,
  AppController app,
  double fraction,
) async {
  final finder = find.byType(Slider).hitTestable();
  await _waitFor(tester, finder, 'production playback slider');
  final slider = tester.widget<Slider>(finder.first);
  final expected = (slider.max * fraction).round();
  final rect = tester.getRect(finder.first);
  await tester.tapAt(Offset(rect.left + rect.width * fraction, rect.center.dy));
  await tester.pump(_pollInterval);
  await _waitForCondition(
    tester,
    () => (app.target.snapshot.position.inMilliseconds - expected).abs() < 1200,
    app,
    'local seek from production slider',
    timeout: const Duration(seconds: 20),
  );
  return app.target.snapshot.position.inMilliseconds;
}

Future<void> _openChat(WidgetTester tester) async {
  if (find.byTooltip('Send message').hitTestable().evaluate().isNotEmpty) {
    return;
  }
  await _tap(
    tester,
    find.widgetWithText(TextButton, 'Chat'),
    'production Chat button',
  );
  await _waitFor(
    tester,
    find.byTooltip('Send message').hitTestable(),
    'production chat composer',
  );
}

Future<void> _closeChatIfNeeded(WidgetTester tester) async {
  final close = find.byTooltip('Close chat').hitTestable();
  if (close.evaluate().isEmpty) return;
  await tester.tap(close);
  await tester.pump(_pollInterval);
  await _waitForConditionWithoutApp(
    tester,
    () => close.evaluate().isEmpty,
    'chat sheet to close',
  );
}

Future<void> _expectChatMessageVisible(
  WidgetTester tester,
  String message,
) async {
  // The phone room also previews the latest message behind the chat sheet.
  final bubble = find.descendant(
    of: find.byType(ChatPanel),
    matching: find.text(message),
  );
  await _waitFor(
    tester,
    bubble.hitTestable(),
    'visible production chat message',
  );
  expect(bubble, findsOneWidget);
  expect(bubble.hitTestable(), findsOneWidget);
}

Future<void> _sendChatThroughUi(
  WidgetTester tester,
  AppController app,
  String message, {
  bool closeAfter = true,
}) async {
  await _openChat(tester);
  final field = find.byType(TextField).hitTestable();
  await _waitFor(tester, field, 'production chat field');
  await tester.enterText(field.last, message);
  await _tap(
    tester,
    find.byTooltip('Send message').hitTestable(),
    'send production chat message',
  );
  await _waitForCondition(
    tester,
    () => app.messages.any((item) => item.isMine && item.text == message),
    app,
    'sent chat message',
  );
  await _expectChatMessageVisible(tester, message);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 200));
  if (closeAfter) await _closeChatIfNeeded(tester);
}

Future<void> _sendReactionThroughUi(WidgetTester tester, String emoji) async {
  await _tap(
    tester,
    find.byTooltip('Send a reaction'),
    'production reaction button',
  );
  await _tap(
    tester,
    find.text(emoji).hitTestable(),
    'production $emoji reaction',
  );
}

Future<void> _waitForRemoteMessage(
  WidgetTester tester,
  AppController app,
  String message,
) => _waitForCondition(
  tester,
  () => app.messages.any((item) => !item.isMine && item.text == message),
  app,
  'remote chat message "$message"',
  timeout: const Duration(seconds: 45),
);

int _checkpointPosition(String? rawValue, String checkpoint) {
  final value = rawValue == null ? null : int.tryParse(rawValue);
  if (value == null || value < 0) {
    throw TestFailure('Invalid position value for checkpoint $checkpoint.');
  }
  return value;
}

void _observe(
  List<Map<String, Object?>> observations,
  AppController app,
  String stage,
) {
  final state = app.target.snapshot;
  observations.add(<String, Object?>{
    'stage': stage,
    'atUtc': DateTime.now().toUtc().toIso8601String(),
    'connected': app.isConnected,
    'peers': app.peers.toList()..sort(),
    'peerMediaCount': app.peerFiles.length,
    'media': state.media?.uri.toString(),
    'positionMs': state.position.inMilliseconds,
    'durationMs': state.duration.inMilliseconds,
    'playing': state.playing,
    'ready': state.ready,
    'buffering': state.buffering,
    'messageCount': app.messages.length,
    'reaction': app.reaction?.emoji,
  });
}

Future<void> _capture(
  NativeScreenshots nativeScreenshots,
  WidgetTester tester,
  List<String> screenshots,
  String stage,
) async {
  final name = '$_role-$stage';
  await tester.pump(const Duration(milliseconds: 250));
  final bytes = await nativeScreenshots.take(tester, name);
  expect(bytes, isNotEmpty, reason: 'Screenshot $name was empty.');
  screenshots.add(name);
}

Future<void> _tap(
  WidgetTester tester,
  Finder finder,
  String description,
) async {
  await _waitFor(tester, finder, description);
  var target = finder.hitTestable();
  if (target.evaluate().isEmpty) {
    await tester.ensureVisible(finder.first);
    await tester.pump(const Duration(milliseconds: 200));
    target = finder.hitTestable();
    await _waitFor(tester, target, '$description to become tappable');
  }
  await tester.tap(target.first);
  await tester.pump(_pollInterval);
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder,
  String description, {
  Duration timeout = const Duration(seconds: 15),
}) => _waitForConditionWithoutApp(
  tester,
  () => finder.evaluate().isNotEmpty,
  description,
  timeout: timeout,
);

Future<Finder> _waitForAny(
  WidgetTester tester,
  List<Finder> finders,
  String description, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  Finder? found;
  await _waitForConditionWithoutApp(
    tester,
    () {
      for (final finder in finders) {
        if (finder.evaluate().isNotEmpty) {
          found = finder;
          return true;
        }
      }
      return false;
    },
    description,
    timeout: timeout,
  );
  return found!;
}

Future<void> _waitForCondition(
  WidgetTester tester,
  bool Function() condition,
  AppController app,
  String description, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    await _waitForConditionWithoutApp(
      tester,
      condition,
      description,
      timeout: timeout,
    );
  } on TestFailure {
    final state = app.target.snapshot;
    throw TestFailure(
      '$_role timed out waiting for $description; '
      'connected=${app.isConnected}, peers=${app.peers}, '
      'playing=${state.playing}, ready=${state.ready}, '
      'positionMs=${state.position.inMilliseconds}, message=${app.message}',
    );
  }
}

Future<void> _waitForConditionWithoutApp(
  WidgetTester tester,
  bool Function() condition,
  String description, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed >= timeout) {
      throw TestFailure(
        'Timed out after ${timeout.inSeconds}s waiting for $description.',
      );
    }
    await tester.pump(_pollInterval);
  }
}
