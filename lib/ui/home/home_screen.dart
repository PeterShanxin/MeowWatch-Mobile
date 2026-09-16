import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../data/app_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.app,
    required this.onJoin,
    required this.onSettings,
    required this.onUpgrade,
    required this.onStartRoom,
    required this.onLocalMode,
    required this.onResume,
    this.onWatchAgain,
  });

  final AppController app;
  final VoidCallback onJoin;
  final VoidCallback onSettings;
  final VoidCallback onUpgrade;
  final Future<void> Function() onStartRoom;
  final Future<void> Function() onLocalMode;
  final Future<void> Function(WatchHistoryEntry entry) onResume;
  final Future<void> Function(WatchHistoryEntry entry)? onWatchAgain;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _actionRunning = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_actionRunning || widget.app.busy) return;
    setState(() => _actionRunning = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _actionRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.app,
      builder: (context, _) {
        final busy = _actionRunning || widget.app.busy;
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tablet =
                    constraints.maxWidth >= 720 &&
                    MediaQuery.textScalerOf(context).scale(16) <= 22.4;
                return SingleChildScrollView(
                  key: const Key('home-scroll-view'),
                  padding: EdgeInsets.fromLTRB(
                    tablet ? 40 : 20,
                    tablet ? 28 : 16,
                    tablet ? 40 : 20,
                    32,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: tablet ? 1180 : 680,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HomeHeader(
                            app: widget.app,
                            onSettings: widget.onSettings,
                            onUpgrade: widget.onUpgrade,
                          ),
                          SizedBox(height: tablet ? 48 : 32),
                          if (tablet)
                            Row(
                              key: const Key('home-tablet-layout'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 10,
                                  child: _InvitationPanel(
                                    tablet: true,
                                    busy: busy,
                                    onStartRoom: () => _run(widget.onStartRoom),
                                    onJoin: widget.onJoin,
                                    onLocalMode: () => _run(widget.onLocalMode),
                                  ),
                                ),
                                SizedBox(
                                  width: constraints.maxWidth >= 1000 ? 48 : 32,
                                ),
                                Expanded(
                                  flex: 9,
                                  child: _HomeHistorySections(
                                    entries: widget.app.repository.history,
                                    busy: busy,
                                    onResume: (entry) =>
                                        _run(() => widget.onResume(entry)),
                                    onWatchAgain: widget.onWatchAgain == null
                                        ? null
                                        : (entry) => _run(
                                            () => widget.onWatchAgain!(entry),
                                          ),
                                  ),
                                ),
                              ],
                            )
                          else ...[
                            _InvitationPanel(
                              tablet: false,
                              busy: busy,
                              onStartRoom: () => _run(widget.onStartRoom),
                              onJoin: widget.onJoin,
                              onLocalMode: () => _run(widget.onLocalMode),
                            ),
                            const SizedBox(height: 36),
                            _HomeHistorySections(
                              entries: widget.app.repository.history,
                              busy: busy,
                              onResume: (entry) =>
                                  _run(() => widget.onResume(entry)),
                              onWatchAgain: widget.onWatchAgain == null
                                  ? null
                                  : (entry) =>
                                        _run(() => widget.onWatchAgain!(entry)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _HomeHistorySections extends StatelessWidget {
  const _HomeHistorySections({
    required this.entries,
    required this.busy,
    required this.onResume,
    required this.onWatchAgain,
  });

  final List<WatchHistoryEntry> entries;
  final bool busy;
  final ValueChanged<WatchHistoryEntry> onResume;
  final ValueChanged<WatchHistoryEntry>? onWatchAgain;

  @override
  Widget build(BuildContext context) {
    final recentRooms = onWatchAgain == null
        ? const <WatchHistoryEntry>[]
        : _recentRoomEntries(entries);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HistorySection(entries: entries, busy: busy, onResume: onResume),
        if (recentRooms.isNotEmpty) ...[
          const SizedBox(height: 32),
          _RecentRoomsSection(
            entries: recentRooms,
            busy: busy,
            onWatchAgain: onWatchAgain!,
          ),
        ],
      ],
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.app,
    required this.onSettings,
    required this.onUpgrade,
  });

  final AppController app;
  final VoidCallback onSettings;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.pets_outlined,
            color: theme.colorScheme.onPrimaryContainer,
            semanticLabel: 'MeowWatch',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'MEOWWATCH',
            style: theme.textTheme.labelLarge?.copyWith(
              letterSpacing: 2.1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (!app.billing.isPlus)
          TextButton.icon(
            onPressed: onUpgrade,
            icon: const Icon(Icons.workspace_premium_outlined, size: 19),
            label: const Text('Plus'),
          ),
        IconButton(
          tooltip: 'Profile and settings',
          onPressed: onSettings,
          icon: const Icon(Icons.account_circle_outlined),
        ),
      ],
    );
  }
}

class _InvitationPanel extends StatelessWidget {
  const _InvitationPanel({
    required this.tablet,
    required this.busy,
    required this.onStartRoom,
    required this.onJoin,
    required this.onLocalMode,
  });

  final bool tablet;
  final bool busy;
  final VoidCallback onStartRoom;
  final VoidCallback onJoin;
  final VoidCallback onLocalMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Movie night,\neven miles apart.',
          style: theme.textTheme.displayMedium?.copyWith(
            fontFamily: 'DMSerifDisplay',
            fontSize: tablet ? 52 : 40,
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w400,
            height: 1.04,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Press play together, chat through every scene, and keep the same room on any screen.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            key: const Key('start-room-button'),
            onPressed: busy ? null : onStartRoom,
            icon: busy
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.add_rounded),
            label: Text(busy ? 'Getting things ready…' : 'Start a room'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 54,
          child: OutlinedButton.icon(
            key: const Key('join-room-button'),
            onPressed: busy ? null : onJoin,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Join a room'),
          ),
        ),
        const SizedBox(height: 18),
        Material(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            key: const Key('local-mode-button'),
            onTap: busy ? null : onLocalMode,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.smartphone_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Local Player Mode',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 3),
                        Text('Watch on this phone without starting a room.'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.entries,
    required this.busy,
    required this.onResume,
  });

  final List<WatchHistoryEntry> entries;
  final bool busy;
  final ValueChanged<WatchHistoryEntry> onResume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Continue Watching',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          entries.isEmpty
              ? 'Your next movie is waiting.'
              : 'Pick up from the moment you left.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        if (entries.isEmpty)
          Padding(
            key: const Key('empty-history'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.movie_filter_outlined,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Pick a video. We’ll save your place.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          )
        else
          ...entries
              .take(5)
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _HistoryCard(
                    entry: entry,
                    enabled: !busy,
                    onTap: () => onResume(entry),
                  ),
                ),
              ),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.entry,
    required this.enabled,
    required this.onTap,
  });

  final WatchHistoryEntry entry;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = entry.duration.inMilliseconds;
    final progress = total <= 0
        ? 0.0
        : (entry.position.inMilliseconds / total).clamp(0.0, 1.0);
    final contextLabel = entry.room == null
        ? 'Local player'
        : 'Room ${entry.room!.config.room}';
    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('resume-${entry.key}'),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      entry.media.isNetwork
                          ? Icons.link_rounded
                          : Icons.movie_outlined,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.media.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '$contextLabel · ${_formatDuration(entry.position)} of ${_formatDuration(entry.duration)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.play_circle_outline_rounded, size: 30),
                ],
              ),
              const SizedBox(height: 14),
              Semantics(
                label: '${(progress * 100).round()} percent watched',
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentRoomsSection extends StatelessWidget {
  const _RecentRoomsSection({
    required this.entries,
    required this.busy,
    required this.onWatchAgain,
  });

  final List<WatchHistoryEntry> entries;
  final bool busy;
  final ValueChanged<WatchHistoryEntry> onWatchAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Recent rooms',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Watch together again',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RecentRoomCard(
              entry: entry,
              enabled: !busy,
              onTap: () => onWatchAgain(entry),
            ),
          ),
      ],
    );
  }
}

class _RecentRoomCard extends StatelessWidget {
  const _RecentRoomCard({
    required this.entry,
    required this.enabled,
    required this.onTap,
  });

  final WatchHistoryEntry entry;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = entry.room!;
    return Semantics(
      button: true,
      enabled: enabled,
      label:
          'Watch ${entry.media.title} together again in room ${room.config.room}',
      hint: 'Starts a new room with this video',
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('watch-again-${room.contextKey}'),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.groups_2_outlined,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.media.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Room ${room.config.room}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Start a new room with this video.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.replay_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Watch together again',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<WatchHistoryEntry> _recentRoomEntries(
  Iterable<WatchHistoryEntry> entries,
) {
  final roomKeys = <String>{};
  final recent = <WatchHistoryEntry>[];
  for (final entry in entries) {
    final room = entry.room;
    if (room == null || !roomKeys.add(room.contextKey)) continue;
    recent.add(entry);
    if (recent.length == 3) break;
  }
  return recent;
}

String _formatDuration(Duration value) {
  final safeSeconds = value.inSeconds.clamp(0, 359999);
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds % 3600) ~/ 60;
  final seconds = safeSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
