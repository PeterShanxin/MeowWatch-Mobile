# Vendored video_player_android

Source: Flutter's [`video_player_android` 2.12.2](https://pub.dev/packages/video_player_android/versions/2.12.2), resolved from pub.dev with lockfile SHA-256 `d27054dea34d748a44f06d433a57005d2aac69944485b0abbaed3303dbcfa3f1`.
Copyright and BSD 3-Clause license remain in `AUTHORS`, source headers, and `LICENSE`.
The MeowWatch-authored `PlayerAudioFocus.java` extension is AGPL-3.0-only.

The package retains its published Android and Dart runtime source, native and
Dart tests, Pigeon definitions/generated source, changelog and package metadata.
The upstream example app and media are omitted.

Local change: a per-player Android `MethodChannel` command
`com.meowwatch.mobile/player_focus` / `setRequireExplicitResume` accepts exactly
`{playerId: int, required: bool}` for a live player created by this plugin.
Each Android player now has one Media3 `AudioFocusManager` as its focus owner;
ExoPlayer's automatic focus handling is disabled. Focus callbacks directly
pause on transient or permanent loss, even when ExoPlayer coalesces playback
events during a queued seek. Local Mode resumes after transient focus returns.
The native callback also reports paused immediately, including when buffering
already made ExoPlayer's `isPlaying` false and no state-change event can fire.
With `setRequireExplicitResume(true)`, Together stays paused until a fresh Play.
Enabling that policy during a transient loss cancels Local Mode's pending resume;
disabling it never starts playback. Explicit Pause cancels pending resume.
Volume ducking, `mixWithOthers` focus opt-out, and per-player disposal remain
supported. The 150 ms video-renderer reset also checks that no pause or focus
interruption occurred before restoring playback.

The native Robolectric CI step uses the hosted Java 21 runtime so the tests
can run against the default Android SDK 36 sandbox. Upstream tests that
explicitly select an older SDK keep their original coverage.
