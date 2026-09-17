# MeowWatch icon

The selected direction is **A / Balanced**: a cream cat outline with blue inner
ears and a blue play button on navy. It follows the owner's preferred reference
and keeps its composition and four whiskers. The final artwork uses flat fills,
consistent outline weight, cleaner ear corners and deliberate empty space. It
contains no gradients, gloss, shadow, texture or lettering.

Three close refinements are retained in the [comparison sheet](../assets/brand/icon-options.png):

| Direction | Difference | Decision |
|---|---|---|
| A / Balanced | Curved cheeks and controlled ear corners | Selected; closest to the reference with a friendly, clean silhouette |
| B / Geometric | Straighter ear sides and firmer corners | A more angular alternative |
| C / Compact | Tighter silhouette and heavier outline | A denser alternative |

The work began with image-guided generation from the owner's reference. Those
studies explored flatter surfaces, stronger small-size recognition and reduced
rounding without changing the cat-and-play concept. The selected design was
rebuilt as editable vector paths so platform exports share the same geometry;
generated raster texture is not part of the shipping artwork.

## Color and source artwork

| Color | Value | Use |
|---|---|---|
| Navy | `#102A43` | Icon background |
| Cream | `#FFF5DF` | Cat outline and whiskers |
| Blue | `#5BA8F5` | Play button and inner ears |

The editable final master is [meowwatch.svg](../assets/brand/meowwatch.svg).
Its canvas is opaque and square. Platform-specific masks and rounded corners
are applied separately; do not bake a phone frame, shadow or lettering into
the master. The app's cinema UI may retain its existing theme colors; these
three colors define the logo artwork.

## Ready-to-use files

| Use | Files |
|---|---|
| Submission / app listing | [1024 × 1024 PNG](../assets/brand/meowwatch-1024.png), [512 × 512 PNG](../assets/brand/meowwatch-512.png); opaque, unmasked square |
| Flutter branding | [256 × 256 PNG](../assets/brand/meowwatch-256.png); square, let the widget apply its corner radius |
| Windows desktop | [Multi-resolution ICO](../assets/brand/meowwatch.ico); 16, 24, 32, 48, 64, 128 and 256 px, transparent outside the rounded navy tile |
| General desktop / artwork | [Desktop SVG](../assets/brand/meowwatch-desktop.svg), [1024 px desktop PNG](../assets/brand/meowwatch-desktop-1024.png) |
| Small UI / favicon | [16–256 px exports](../assets/brand/png/); 16, 24 and 32 px use a heavier outline and omit inner-ear/whisker detail |
| Monochrome | [White mark SVG](../assets/brand/meowwatch-monochrome.svg), [1024 px transparent PNG](../assets/brand/meowwatch-monochrome-1024.png), [simplified white SVG](../assets/brand/meowwatch-small-monochrome.svg) |
| Android adaptive layers | [Foreground SVG](../assets/brand/android/foreground.svg), [background SVG](../assets/brand/android/background.svg), [monochrome SVG](../assets/brand/android/monochrome.svg), plus 432 px foreground/background PNGs |
| Review | [Options and masks](../assets/brand/icon-options.png), [actual pixel size checks](../assets/brand/icon-size-checks.png), [export manifest](../assets/brand/exports.json) |

The desktop pack is ready for the companion project, but this change does not
edit or replace assets in the desktop reference checkout.

## Android integration

The existing manifest still points at `@mipmap/ic_launcher`. That reference now
resolves to the appropriate resource for the platform:

- API 25 and earlier: five legacy density PNGs, 48–192 px.
- API 26 and later: native vector foreground and solid navy background in
  `mipmap-anydpi-v26/ic_launcher.xml`.
- API 33 and later: `mipmap-anydpi-v33/ic_launcher.xml` also supplies a monochrome
  vector for launchers that support themed icons.

The adaptive layers use a 108 dp canvas. The visible foreground fits inside
the central 66 dp **circle**, including the ears; it is not merely checked
against a square. The generator verifies rasterized visible pixels against
that bound. Circle and rounded-square previews show the central 72 dp viewport.
Android applies the actual launcher mask and theme tint. These dimensions and
layer choices follow the [official adaptive icon guidance](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)
and [AdaptiveIconDrawable viewport documentation](https://developer.android.com/reference/android/graphics/drawable/AdaptiveIconDrawable).

The preview images demonstrate asset geometry. A compiled APK and an actual
launcher/splash render are separate runtime checks.
The older Android launch background references the icon as a drawable layer,
not a bitmap, so API 26–30 can inflate the adaptive resource. The install matrix
also includes API 29 to exercise this pre-Android-12 splash path.

## Rebuild

Use Node.js and `sharp` (the committed manifest records the rendering versions).
The following installs the pinned renderer outside the application dependency
tree:

```powershell
npm install --prefix .local/brand-tools --no-save --package-lock=false sharp@0.35.4
$env:NODE_PATH = Join-Path (Get-Location) '.local/brand-tools/node_modules'
node tools/generate_brand.cjs
```

Edit the master SVG, or the small-size and alternative SVGs, then run the
generator. Keep the mark as direct path children of its `id="mark"` group so
the SVG-to-Android export preserves fills and strokes. The generator writes
PNG, ICO and Android XML resources, previews and a manifest with source/export
hashes, dimensions and safe-area results. PNG compression may vary with the
renderer version; use the recorded version for byte-for-byte regeneration.

Review the actual-size sheet at 100% scale. For 16–32 px uses choose the
simplified exports; use the full mark at 48 px and above. White monochrome
artwork needs a contrasting surface or a platform-applied tint.
