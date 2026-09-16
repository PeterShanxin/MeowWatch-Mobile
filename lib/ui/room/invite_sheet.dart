import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_controller.dart';

Future<void> showInviteSheet(BuildContext context, AppController app) async {
  final invite = app.invite;
  final room = app.room;
  if (invite == null || room == null) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Save them a seat.',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 12),
          const Text('Send this invite. Joining your room is always free.'),
          const SizedBox(height: 24),
          Center(
            child: Semantics(
              label: 'QR invite to ${room.config.room}',
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: QrImageView(
                  data: invite.toString(),
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SelectableText(
            room.config.room,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () async {
              try {
                final box = context.findRenderObject() as RenderBox?;
                await SharePlus.instance.share(
                  ShareParams(
                    text: 'Movie night? Join me on MeowWatch.\n$invite',
                    title: 'MeowWatch room invite',
                    sharePositionOrigin: box == null
                        ? null
                        : box.localToGlobal(Offset.zero) & box.size,
                  ),
                );
              } catch (_) {
                app.report('Could not open sharing. Use Copy invite instead.');
              }
            },
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Share invite'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: invite.toString()));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Invite copied.')));
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy invite'),
          ),
        ],
      ),
    ),
  );
}
