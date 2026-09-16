import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/cast/cast_playback_target.dart';

enum PlaybackDeviceChoice { phone, nearby, cast }

Future<PlaybackDeviceChoice?> showPlaybackDevicesSheet(
  BuildContext context, {
  required AppController app,
}) => showModalBottomSheet<PlaybackDeviceChoice>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (context) => PlaybackDevicesSheet(app: app),
);

class PlaybackDevicesSheet extends StatelessWidget {
  const PlaybackDevicesSheet({super.key, required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) {
      final media = app.target.snapshot.media;
      final castReason = app.isNearby
          ? 'Return to this phone before connecting a TV.'
          : media == null
          ? 'Open a public HTTPS MP4 video on this phone first.'
          : !CastPlaybackTarget.supports(media)
          ? CastPlaybackTarget.unsupportedMessage
          : null;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose your screen',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Keep your room and people together while changing where you watch.',
            ),
            const SizedBox(height: 24),
            _DeviceOption(
              key: const Key('playback-device-phone'),
              icon: Icons.smartphone_rounded,
              title: 'This phone',
              description: app.isNearby || app.isCasting
                  ? 'Return here paused, ready to continue.'
                  : 'Video and controls stay on this device.',
              selected: !app.isNearby && !app.isCasting,
              onTap: () => Navigator.pop(context, PlaybackDeviceChoice.phone),
            ),
            const Divider(height: 24),
            _DeviceOption(
              key: const Key('playback-device-nearby'),
              icon: Icons.desktop_windows_outlined,
              title: 'Nearby MeowWatch',
              description: app.isCasting
                  ? 'Return to this phone before connecting a desktop.'
                  : app.isNearby
                  ? app.nearby!.label
                  : 'Pair with your desktop on the same private Wi-Fi.',
              selected: app.isNearby,
              onTap: app.isCasting
                  ? null
                  : () => Navigator.pop(context, PlaybackDeviceChoice.nearby),
            ),
            const Divider(height: 24),
            _DeviceOption(
              key: const Key('playback-device-cast'),
              icon: Icons.cast_rounded,
              title: app.isCasting ? 'Manage TV connection' : 'Google Cast',
              description: app.isCasting
                  ? app.cast!.connected
                        ? app.cast!.receiverName
                        : 'TV disconnected. Return to this phone to reconnect.'
                  : castReason ??
                        'Choose a compatible TV on the same Wi-Fi. The TV opens your public MP4 link.',
              selected: app.isCasting,
              onTap: (app.isCasting ? app.cast!.connected : castReason == null)
                  ? () => Navigator.pop(context, PlaybackDeviceChoice.cast)
                  : null,
            ),
          ],
        ),
      );
    },
  );
}

class _DeviceOption extends StatelessWidget {
  const _DeviceOption({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String title, description;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 6),
    leading: Icon(icon),
    title: Text(title),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(description),
    ),
    trailing: selected
        ? const Icon(
            Icons.check_circle_rounded,
            semanticLabel: 'Current screen',
          )
        : null,
    onTap: onTap,
    enabled: onTap != null,
  );
}
