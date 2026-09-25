import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_settings.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';

import '../support/sync_playback_fakes.dart';
import '../ui/home/ui_test_support.dart';

AppController _app(AppRepository repository, UiTestBilling billing) =>
    AppController(
      repository: repository,
      billing: billing,
      hosting: UiTestHosting(),
      phone: SyncTestTarget(),
      endpointSettings: MemoryEndpointSettings(),
    );

void main() {
  test(
    'premium appearance persists and falls back when Plus expires',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'meowwatch-appearance-',
      );
      final file = File('${directory.path}/history.json');
      var billing = UiTestBilling();
      var app = _app(AppRepository(file), billing);
      try {
        await expectLater(app.selectTheme('cinemaNoir'), throwsStateError);
        expect(app.repository.theme, 'cozy');
        billing.plus = true;
        await app.selectTheme('cinemaNoir');
        await app.close();
        final reopened = AppRepository(file);
        await reopened.read();
        billing = UiTestBilling()..plus = true;
        app = _app(reopened, billing);
        expect(app.theme, 'cinemaNoir');
        billing.plus = false;
        expect(app.theme, 'cozy');
        expect(app.repository.theme, 'cinemaNoir');
        await expectLater(app.selectTheme('glassAurora'), throwsStateError);
        billing.plus = true;
        expect(app.theme, 'cinemaNoir');
        await app.selectTheme('cozy');
        expect(app.theme, 'cozy');
      } finally {
        await app.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('failed appearance save leaves the previously selected theme', () async {
    final repository = _FailingRepository();
    final billing = UiTestBilling()..plus = true;
    final app = _app(repository, billing);
    try {
      await expectLater(
        app.selectTheme('glassAurora'),
        throwsA(isA<FileSystemException>()),
      );
      expect(app.theme, 'cozy');
      await expectLater(app.selectTheme('unknown'), throwsFormatException);
    } finally {
      await app.close();
    }
  });

  test(
    'temporary share permission does not create an unusable resume entry',
    () async {
      final fixture = UiTestApp.create();
      try {
        await fixture.controller.useLocalMode();
        await fixture.controller.load(
          MediaItem(
            uri: Uri.parse('content://test.documents/temporary-video'),
            title: 'Shared video',
            canRemember: false,
          ),
        );
        await fixture.controller.saveProgress();
        expect(fixture.repository.history, isEmpty);
        await fixture.controller.load(
          MediaItem.fromUrl('https://example.com/video.mp4'),
        );
        await fixture.controller.saveProgress();
        expect(fixture.repository.history.single.media.canRemember, isTrue);
      } finally {
        await fixture.close();
      }
    },
  );

  test('older saved media remains resumable without the new grant flag', () {
    final media = MediaItem.fromJson({
      'uri': 'content://test.documents/saved-video',
      'title': 'Saved video',
    });
    expect(media.canRemember, isTrue);
  });
}

class _FailingRepository extends UiTestRepository {
  @override
  Future<void> save() async =>
      throw const FileSystemException('Disk unavailable');
}
