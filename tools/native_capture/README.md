# Android screenshots during native recording

Use one `NativeScreenshots` instance **inside each `testWidgets` body**:

```dart
final screenshots = NativeScreenshots(binding);
// Run the actual app and interact with it normally.
await screenshots.take(tester, 'room-playing');
```

Remove standalone `binding.convertFlutterSurfaceToImage()` calls. Capture calls
must be awaited and must not overlap. Do not share the helper across test cases.
The helper leaves screenshot bytes, names, `reportData` and the
`integrationDriver` callback with the ordinary `binding.takeScreenshot` path.
It does not replace frames, manipulate video, or change production rendering.

## Flutter 3.44.0 boundary

The repository pins Flutter 3.44.0. Its Android screenshot implementation
converts the normal surface into a `FlutterImageView`; screenshot acquisition
explicitly acquires an image frame. Leaving that mode active throughout a test
can leave an external Android screen recording showing an earlier image even
while the Dart test is progressing. The public Dart conversion method registers
one test teardown and keeps its internal `_isSurfaceRendered` flag until that
teardown. Calling it again for each screenshot would assert or register duplicate
teardowns.

The helper calls the public conversion method on the first screenshot only.
Further screenshots invoke the same native conversion method directly. Every
capture attempts `revertFlutterImage` in `finally`, including a failed conversion
or failed screenshot. The SDK's own final teardown remains registered; the
native revert is a no-op when already reverted.

The native revert method acknowledges its channel call before FlutterView's
first rendered-frame callback resets its conversion flag. The helper explicitly
schedules and pumps a frame before capture and after reverting, followed by
another frame after 100 ms to let normal rendering resume. Explicit scheduling
also matters in automated widget tests: pumping alone only draws when a frame
is already scheduled. This settling
period is not a native completion acknowledgement. A fresh Android run and
visual inspection of the original screen recording must still establish that
frames continue to update between screenshots. Unit tests only establish helper
ordering, delegation and cleanup.

The channel methods used here are implementation details, not a stable Flutter
API. Review these exact upstream sources before changing the Flutter pin:

- [Dart screenshot state and test teardown](https://github.com/flutter/flutter/blob/3.44.0/packages/integration_test/lib/src/_callback_io.dart#L61-L98)
- [Public screenshot reporting contract](https://github.com/flutter/flutter/blob/3.44.0/packages/integration_test/lib/integration_test.dart#L182-L205)
- [Native channel dispatch](https://github.com/flutter/flutter/blob/3.44.0/packages/integration_test/android/src/main/java/dev/flutter/plugins/integration_test/IntegrationTestPlugin.java#L78-L92)
- [Native conversion, revert and image acquisition](https://github.com/flutter/flutter/blob/3.44.0/packages/integration_test/android/src/main/java/dev/flutter/plugins/integration_test/FlutterDeviceScreenshot.java#L101-L122)
- [FlutterView's asynchronous revert](https://github.com/flutter/flutter/blob/3.44.0/engine/src/flutter/shell/platform/android/io/flutter/embedding/android/FlutterView.java#L1399-L1445)
- [Automated binding only draws scheduled frames](https://github.com/flutter/flutter/blob/3.44.0/packages/flutter_test/lib/src/binding.dart#L2248-L2264)

Run the focused contract with:

```sh
flutter test --no-pub test/tools/native_screenshot_test.dart
```

The helper and tests do not establish native recording freshness or decoder
correctness. Preserve that distinction in acceptance reports.
