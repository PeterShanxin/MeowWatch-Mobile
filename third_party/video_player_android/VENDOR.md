# Vendored video_player_android

Source: Flutter's [`video_player_android` 2.12.2](https://pub.dev/packages/video_player_android/versions/2.12.2), resolved from pub.dev with lockfile SHA-256 `d27054dea34d748a44f06d433a57005d2aac69944485b0abbaed3303dbcfa3f1`.
Copyright and BSD 3-Clause license remain in `AUTHORS`, source headers, and `LICENSE`.

The package retains its published Android and Dart runtime source, native and
Dart tests, Pigeon definitions/generated source, changelog and package metadata.
The upstream example app and media are omitted.

Local change: a per-player Android `MethodChannel` command
`com.meowwatch.mobile/player_focus` / `setRequireExplicitResume` accepts exactly
`{playerId: int, required: bool}` for a live player created by this plugin.
When enabled, transient audio-focus playback suppression pauses its ExoPlayer
immediately, including when the policy is enabled during suppression. The
default is disabled; disabling does not start playback. Other suppression
reasons and upstream ExoPlayer audio-focus/mix behavior remain unchanged.
