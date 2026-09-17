# Media source support and webpage extraction decision

**Evaluated:** 2026-09-16

**Scope:** Android-first Shipaton build

## Decision

MeowWatch Mobile supports Android video files and direct HTTP(S) media URLs in
this build. It does **not** claim support for general webpage URLs such as a
YouTube or Bilibili watch page.

This closes the P2 evaluation required by the product specification. The
specification says to evaluate webpage extraction separately, keep direct
URLs/files reliable, and excludes “a mobile yt-dlp port merely for feature
parity.” On that basis, implementing a general extractor in this build is not a
sound scope choice. It would add a second runtime and playback contract without
being required for the mobile product journey, and it could not honestly be
presented as broad webpage support without substantially more compatibility and
device evidence.

This is not a claim that yt-dlp can never run inside an Android app. Community
integrations demonstrate a feasible route by embedding CPython and yt-dlp in an
Android library. That is a different architecture from the desktop app and
would need to be adopted and maintained deliberately. The desktop provisioner
cannot be reused as-is: it downloads Windows `yt-dlp.exe` and Deno binaries,
while the official yt-dlp and Deno release matrices do not publish Android
executables.

Even an embedded Android yt-dlp package would not complete the feature by
itself:

- Full YouTube extraction requires the matching `yt-dlp-ejs` component and a
  supported JavaScript runtime. An Android embedding must provide and maintain
  that runtime rather than assume the desktop Deno setup exists.
- yt-dlp can return separate video and audio streams plus required HTTP headers.
  The mobile player currently opens one URI and supplies no custom headers.
- Extractors change with sites and need frequent updates. Bundling them avoids
  downloading executable code after install, but makes extractor/runtime
  updates application releases and expands ABI, size, license, and device-test
  obligations.
- Login, cookies, private media, regional access, and DRM remain outside the
  product contract. A technically extractable result does not establish the
  right to play or share it.

No unreviewed resolver backend or arbitrary-page WebView interception is an
acceptable shortcut. A backend would add SSRF, abuse, privacy, rate-limit, cost,
and availability responsibilities. Web scraping or traffic interception would
be brittle and risk exposing authenticated browser state.

## What the app implements now

The first-launch screen offers a short, skippable guide that can be replayed
from Settings without leaving a room or resetting playback. **Choose what to
watch** includes an explicit **Try a short film** action for the unmodified
[Sintel trailer](https://download.blender.org/durian/trailer/sintel_trailer-480p.mp4).
It returns the same `MediaItem` used by ordinary file/link selection, so room,
history and quota behavior follow the normal load path. Opening the picker
itself starts no download. The 52-second, approximately 4.4 MB sample is credited
to Blender Foundation under CC BY 3.0 in the picker and in-app license list.
HTTP range access and H.264/AAC metadata have been checked; the native playback
gate also exercises this exact public URL before accepting its Android support.

Source hints use generic Material symbols plus the actual URL host, with named
labels for direct Blender download and Internet Archive download links.
These are source identification, not third-party platform logos, an endorsement,
or a guarantee of decoding. Watch pages retain the unsupported-link behavior.

| Source | Current behavior | Practical limit |
| --- | --- | --- |
| Android-picked or shared video | **Video on this device** opens a `content://` URI through `video_player`. The Android bridge requires a video MIME type and read permission. | Continue Watching is durable only when Android grants persistent access. Codec support depends on the device. |
| Direct HTTP or HTTPS media URL | **Direct video link** accepts an HTTP(S) URI with a host and passes it to `VideoPlayerController.networkUrl`. | This is a direct-media path, not an HTML extractor. The app does not probe MIME type, attach request headers, manage cookies, or combine separate audio and video streams. |
| Android Share/Open URL | Accepts a video MIME type or a URL whose path ends in `.mp4`, `.m4v`, `.mov`, `.webm`, `.mkv`, `.3gp`, `.m3u8`, or `.mpd`. | An extension or MIME type is an input filter, not proof that the device can decode the stream. |
| Peer link in chat | Offers **Watch this too** only for a standalone direct URL ending in `.mp4`, `.m4v`, `.webm`, `.mov`, `.mkv`, `.m3u8`, or `.mpd`, after showing the host and asking for confirmation. | Each peer fetches the media from the origin. Redirects can contact another host, and HTTP is unencrypted. |
| Cast | Accepts a public HTTPS `.mp4` URL without credentials, query, or fragment. | Local files, private/LAN URLs, webpages, signed query URLs, and other stream types are not claimed as Cast-compatible. |

The Android player uses ExoPlayer through Flutter's `video_player`. ExoPlayer
supports common progressive containers plus HLS and DASH, subject to the
contained codec and the device decoder. Current native evidence proves the
checked fixtures and flows recorded in `docs/STATUS.md`; it does not prove every
extension, codec, CDN, redirect, or Android device.

## Actual fallback and error behavior

The shipped fallback is:

1. Choose a video with **Video on this device**; or
2. paste a direct HTTP(S) media URL under **Direct video link**; or
3. receive a qualifying direct video URL through Android Share/Open or the
   room chat's confirmed **Watch this too** action.

Known webpage/protected-streaming hosts are rejected before load with the
current direct-link explanation:

> This is a webpage, not a direct video. Choose a video file or a direct media
> link. Protected streaming services are not supported.

If a network source reaches the player but cannot initialize, the current
readable error tells the user to check the connection and use a direct video
link rather than a webpage. The app does not currently offer an **Open webpage
in browser** recovery action. A failed `target.load` also does not preserve the
previous player instance.

`MediaItem.fromUrl` rejects credentials and several known webpage or protected
streaming hosts, but it does not positively identify direct media. Other HTML
pages can pass the scheme/host check, replace the current controller, and fail
during player initialization. Those pages are unsupported; the fallback is the
resulting readable load error and another file/direct-link choice. Tightening
this classifier would improve the fallback, but that improvement is not claimed
as implemented here.

## Unsupported sources in this build

- General watch-page URLs, including YouTube and Bilibili pages.
- Netflix, Disney+, Prime Video, and other DRM-protected services.
- Login-gated, private, age-gated, subscription-only, cookie-dependent, or
  region-bypassing media.
- Pages or streams that require browser JavaScript, browser fingerprinting,
  `Referer`/custom request headers, or separate audio and video streams.
- `blob:`, `data:`, `javascript:`, FTP, and other non-HTTP(S) network schemes.
- Guaranteed playback based on a filename extension alone. Container, codec,
  profile, resolution, and hardware decoder support all matter.

## Technical evaluation

| Approach | Finding |
| --- | --- |
| Reuse the desktop provisioner | Not compatible. It provisions Windows executables and relies on desktop process behavior. |
| Embed CPython and yt-dlp in Android | Technically feasible through community Android packaging, so lack of an official Android binary is not an absolute blocker. It is still a new maintained runtime with size, ABI, EJS/JavaScript, update, license, and physical-device obligations. It is outside this build's specified mobile scope. |
| Build dedicated Android yt-dlp/JS artifacts | Technically possible as a maintained toolchain project, but not supplied by the upstream release matrices. It needs reproducible multi-ABI builds and Android compatibility validation. It is not justified merely to match desktop. |
| Resolve on a new backend | No reviewed backend exists. Adding one would expand product, security, privacy, operations, and cost scope. |
| Inspect arbitrary pages in a WebView | Not a reliable general resolver and introduces untrusted-page/authenticated-state risk. |
| Keep files and direct URLs reliable | The implemented fallback and the correct scope for this build. |

## Primary references

- [yt-dlp release files and licensing](https://github.com/yt-dlp/yt-dlp#release-files)
- [yt-dlp external JavaScript setup](https://github.com/yt-dlp/yt-dlp/wiki/EJS)
- [Community Android CPython/yt-dlp packaging example](https://github.com/ffmpegkit-maintained/yt-dlp-android)
- [Deno supported installation binaries](https://docs.deno.com/runtime/getting_started/installation/#manual-download)
- [Flutter `video_player` Android behavior](https://docs.flutter.dev/cookbook/plugins/play-video)
- [Android ExoPlayer supported formats](https://developer.android.com/media/media3/exoplayer/supported-formats)
- [Android dynamic-code-loading guidance](https://developer.android.com/privacy-and-security/risks/dynamic-code-loading)
- [Google Play SDK policy examples](https://support.google.com/googleplay/android-developer/answer/13323374)

Repository evidence used for this decision: `docs/PRODUCT_SPEC.md`,
`lib/core/media/media_item.dart`, `lib/core/media/media_picker.dart`,
`lib/app/incoming_media.dart`, `lib/core/chat/shared_video_link.dart`,
`lib/core/playback/local_mobile_target.dart`,
`lib/core/cast/cast_playback_target.dart`, and the desktop reference's
`lib/core/resolve/` implementation. The desktop checkout was inspected
read-only.
