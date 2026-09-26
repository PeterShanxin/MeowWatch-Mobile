import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/media/sample_video.dart';
import '../brand_mark.dart';

const meowWatchVersion = '0.1.1+2';
const meowWatchSourceUrl = 'https://github.com/PeterShanxin/MeowWatch-Mobile';
const meowWatchSyncCoreSourceUrl =
    'https://github.com/PeterShanxin/MeowWatch/tree/'
    'c7cc4be5203abe28fb1cd043c286367fd1e3ba46';

const bundledLicenseAssets = <String, List<String>>{
  'LICENSE': <String>['MeowWatch'],
  'assets/fonts/DMSans-OFL.txt': <String>['DM Sans'],
  'assets/fonts/DMSerifDisplay-OFL.txt': <String>['DM Serif Display'],
};

bool _licensesRegistered = false;

/// Registers licenses that Flutter cannot discover from package metadata.
///
/// The three text files in [bundledLicenseAssets] must also be declared as
/// Flutter assets. Package licenses continue to come from Flutter's generated
/// license registry.
void registerMeowWatchLicenses() {
  if (_licensesRegistered) return;
  _licensesRegistered = true;
  for (final entry in bundledLicenseAssets.entries) {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(
        entry.value,
        await rootBundle.loadString(entry.key),
      );
    });
  }
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Sintel sample trailer (streamed)'],
      '$sampleVideoCredit\n\n'
      'Unmodified official trailer: $sampleVideoUrl\n'
      'Source and sharing terms: $sampleVideoLicenseUrl\n'
      'Creative Commons Attribution 3.0: '
      'https://creativecommons.org/licenses/by/3.0/',
    );
  });
}

Future<void> showAboutSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.68),
    builder: (_) => const AboutSheet(),
  );
}

class AboutSheet extends StatelessWidget {
  const AboutSheet({super.key, this.onShowLicenses});

  final VoidCallback? onShowLicenses;

  void _licenses(BuildContext context) {
    final callback = onShowLicenses;
    if (callback != null) {
      callback();
      return;
    }
    registerMeowWatchLicenses();
    showLicensePage(
      context: context,
      applicationName: 'MeowWatch',
      applicationVersion: meowWatchVersion,
      applicationLegalese: 'Licensed under AGPL-3.0-only.',
      applicationIcon: const MeowWatchMark(size: 54),
    );
  }

  Future<void> _copy(BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 620,
            maxHeight:
                (media.size.height - media.viewInsets.bottom).clamp(
                  0,
                  double.infinity,
                ) *
                0.94,
          ),
          child: Material(
            color: colors.surface,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: SingleChildScrollView(
              key: const Key('about-sheet-scroll-view'),
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'About MeowWatch',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _AboutCard(
                    child: Row(
                      children: [
                        const MeowWatchMark(size: 42),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'MeowWatch',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text('Version $meowWatchVersion'),
                              SizedBox(height: 3),
                              Text('AGPL-3.0-only'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _AboutCard(
                    child: Material(
                      type: MaterialType.transparency,
                      child: ExpansionTile(
                        key: const Key('whats-new-expansion'),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 8),
                        title: const Text('What’s new'),
                        subtitle: const Text('In version $meowWatchVersion'),
                        children: const [
                          Text(
                            'Start a movie night with a room invitation, synchronized '
                            'playback and chat. Pick up where you left off with '
                            'Continue Watching, or open a video shared from another app.\n\n'
                            'MeowWatch Plus adds unlimited hosting, Cinema Noir and '
                            'Glass Aurora themes, and Movie night reactions.',
                            style: TextStyle(height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _PrivacyCard(),
                  const SizedBox(height: 14),
                  _AboutCard(
                    title: 'Source & licenses',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'MeowWatch is open source. The portable Syncplay core '
                          'is adapted from desktop MeowWatch at the pinned '
                          'revision shown below.',
                          style: TextStyle(height: 1.45),
                        ),
                        const SizedBox(height: 14),
                        _SourceRow(
                          label: 'Mobile source',
                          value: meowWatchSourceUrl,
                          onCopy: () => _copy(
                            context,
                            'Mobile source link',
                            meowWatchSourceUrl,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _SourceRow(
                          label: 'Syncplay core source',
                          value: meowWatchSyncCoreSourceUrl,
                          onCopy: () => _copy(
                            context,
                            'Syncplay source link',
                            meowWatchSyncCoreSourceUrl,
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          key: const Key('open-source-licenses-button'),
                          onPressed: () => _licenses(context),
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('Open source licenses'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Package licenses and bundled font licenses are '
                          'available on the next screen. Static notices are '
                          'also published with the source code.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.onSurfaceVariant,
                                height: 1.4,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) => const _AboutCard(
    title: 'Privacy at a glance',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PrivacyItem(
          icon: Icons.phone_android_outlined,
          title: 'On this device',
          body:
              'Your display name, watch history, resume positions and saved '
              'room details are stored in MeowWatch’s local app storage.',
        ),
        SizedBox(height: 14),
        _PrivacyItem(
          icon: Icons.groups_outlined,
          title: 'Together Rooms',
          body:
              'Your display name, room identity, playback state and chat are '
              'sent through the configured public Syncplay server so the room '
              'can stay in sync.',
        ),
        SizedBox(height: 14),
        _PrivacyItem(
          icon: Icons.workspace_premium_outlined,
          title: 'RevenueCat',
          body:
              'RevenueCat handles an SDK-generated anonymous app user ID and '
              'store, purchase and entitlement data needed to show, buy and '
              'restore MeowWatch Plus.',
        ),
        SizedBox(height: 14),
        _PrivacyItem(
          icon: Icons.desktop_windows_outlined,
          title: 'Nearby MeowWatch',
          body:
              'Nearby discovery runs on your local network. After you use a '
              'desktop invitation and approve pairing, MeowWatch stores a '
              'protected pairing credential and sends controls, session state '
              'and chat to that paired desktop over the LAN. A paired desktop '
              'in a Together Room still uses that room’s Syncplay server.',
        ),
      ],
    ),
  );
}

class _PrivacyItem extends StatelessWidget {
  const _PrivacyItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 22, color: Theme.of(context).colorScheme.secondary),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(body, style: const TextStyle(height: 1.4)),
          ],
        ),
      ),
    ],
  );
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  value,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy $label link',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
    ),
  );
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    ),
  );
}
