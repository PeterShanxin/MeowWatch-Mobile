import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/media/media_item.dart';
import '../../core/media/media_picker.dart';
import '../../core/media/sample_video.dart';

Future<MediaItem?> showMediaSheet(
  BuildContext context, {
  required AppController app,
}) async {
  ModalRoute<MediaItem>? sheetRoute;
  final media = await showModalBottomSheet<MediaItem>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.68),
    builder: (context) {
      sheetRoute = ModalRoute.of<MediaItem>(context);
      return _MediaSheet(app: app);
    },
  );
  // Keep the player intact until the picker has removed its overlay entries.
  await sheetRoute?.completed;
  return media;
}

class _MediaSheet extends StatefulWidget {
  const _MediaSheet({required this.app});

  final AppController app;

  @override
  State<_MediaSheet> createState() => _MediaSheetState();
}

class _MediaSheetState extends State<_MediaSheet> {
  final _url = TextEditingController();
  final _picker = MediaPicker();
  String? _error;
  bool _picking = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final media = await _picker.pickVideo();
      if (mounted && media != null) Navigator.of(context).pop(media);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not open the video picker. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _acceptUrl() {
    try {
      final media = MediaItem.fromUrl(_url.text);
      Navigator.of(context).pop(media);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
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
            maxWidth: 560,
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
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Choose what to watch',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        onPressed: _picking
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close, color: colors.onSurface),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.app.isLocal
                        ? 'Play on this phone now. You can bring the same video into a room later.'
                        : 'Everyone stays together when you load a compatible source.',
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.72),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('open-sample-video'),
                      onPressed: _picking
                          ? null
                          : () => Navigator.of(context).pop(sampleVideo()),
                      icon: const Icon(Icons.smart_display_outlined),
                      label: const Text('Try a short film · 52 seconds'),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 16),
                    child: Text(
                      'Sintel trailer · Blender Open Movies\n'
                      'A 4.4 MB sample to try the player and room controls.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                  _ChoiceCard(
                    icon: Icons.video_file_outlined,
                    title: 'Video on this device',
                    detail: 'Choose a video file supported by Android.',
                    trailing: _picking
                        ? SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.primary,
                            ),
                          )
                        : Icon(Icons.chevron_right, color: colors.primary),
                    onTap: _picking ? null : _pickFile,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.link, color: colors.secondary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Direct video link',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: colors.onSurface,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Use an HTTP or HTTPS link that points directly to a playable media file.',
                          style: TextStyle(
                            color: colors.onSurface.withValues(alpha: 0.68),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _url,
                          enabled: !_picking,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.url],
                          autocorrect: false,
                          style: TextStyle(color: colors.onSurface),
                          cursorColor: colors.primary,
                          onChanged: (_) {
                            setState(() => _error = null);
                          },
                          onSubmitted: (_) => _acceptUrl(),
                          decoration: InputDecoration(
                            hintText: 'https://example.com/movie.mp4',
                            hintStyle: TextStyle(
                              color: colors.onSurface.withValues(alpha: 0.55),
                            ),
                            filled: true,
                            fillColor: colors.surface,
                            errorText: _error,
                            errorMaxLines: 4,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colors.onSurface.withValues(alpha: 0.22),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colors.primary,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        if (_url.text.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _SourceHint(value: _url.text),
                        ],
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.primary,
                            foregroundColor: colors.surface,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _picking ? null : _acceptUrl,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Use this link'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: colors.secondary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Webpages and DRM-protected streaming services are not supported.',
                          style: TextStyle(
                            color: colors.onSurface.withValues(alpha: 0.62),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('About the sample film'),
                        content: const SelectableText(
                          '$sampleVideoTitle\n\n$sampleVideoCredit\n\n'
                          'The original trailer is streamed directly from '
                          'download.blender.org. It is not modified.\n\n'
                          'Source and license: $sampleVideoLicenseUrl\n'
                          'https://creativecommons.org/licenses/by/3.0/',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text('Sample film credits'),
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

class _SourceHint extends StatelessWidget {
  const _SourceHint({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return const SizedBox.shrink();
    }
    final host = uri.host.toLowerCase();
    final direct = RegExp(
      r'\.(mp4|m4v|webm|mov|mkv|m3u8|mpd)$',
      caseSensitive: false,
    ).hasMatch(uri.path);
    final (icon, label) = switch (host) {
      'download.blender.org' when direct => (
        Icons.movie_outlined,
        'Blender Open Movies · direct media',
      ),
      'archive.org' when direct && uri.path.startsWith('/download/') => (
        Icons.account_balance_outlined,
        'Internet Archive · direct media',
      ),
      _ => (Icons.language_outlined, host),
    };
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 76),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(icon, color: colors.primary, size: 30),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.66),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
