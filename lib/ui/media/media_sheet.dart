import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/media/media_item.dart';
import '../../core/media/media_picker.dart';

const _navy = Color(0xFF10141F);
const _raised = Color(0xFF1A2232);
const _ivory = Color(0xFFF5EDE0);
const _apricot = Color(0xFFEFB38C);
const _lavender = Color(0xFFB9A9D3);

Future<MediaItem?> showMediaSheet(
  BuildContext context, {
  required AppController app,
}) => showModalBottomSheet<MediaItem>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: 0.68),
  builder: (_) => _MediaSheet(app: app),
);

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
            color: _navy,
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
                                color: _ivory,
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
                        icon: const Icon(Icons.close, color: _ivory),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.app.isLocal
                        ? 'Play on this phone now. You can bring the same video into a room later.'
                        : 'Everyone stays together when you load a compatible source.',
                    style: TextStyle(
                      color: _ivory.withValues(alpha: 0.72),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _ChoiceCard(
                    icon: Icons.video_file_outlined,
                    title: 'Video on this device',
                    detail: 'Choose a video file supported by Android.',
                    trailing: _picking
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _apricot,
                            ),
                          )
                        : const Icon(Icons.chevron_right, color: _apricot),
                    onTap: _picking ? null : _pickFile,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _raised,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.link, color: _lavender),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Direct video link',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: _ivory,
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
                            color: _ivory.withValues(alpha: 0.68),
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
                          style: const TextStyle(color: _ivory),
                          cursorColor: _apricot,
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                          onSubmitted: (_) => _acceptUrl(),
                          decoration: InputDecoration(
                            hintText: 'https://example.com/movie.mp4',
                            hintStyle: TextStyle(
                              color: _ivory.withValues(alpha: 0.55),
                            ),
                            filled: true,
                            fillColor: _navy,
                            errorText: _error,
                            errorMaxLines: 4,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: _ivory.withValues(alpha: 0.22),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: _apricot,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _apricot,
                            foregroundColor: _navy,
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
                      const Icon(
                        Icons.info_outline,
                        color: _lavender,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Webpages and DRM-protected streaming services are not supported.',
                          style: TextStyle(
                            color: _ivory.withValues(alpha: 0.62),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
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
  Widget build(BuildContext context) => Material(
    color: _raised,
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
              Icon(icon, color: _apricot, size: 30),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _ivory,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: TextStyle(
                        color: _ivory.withValues(alpha: 0.66),
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
