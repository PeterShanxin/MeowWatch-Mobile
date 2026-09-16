# Mobile design direction

MeowWatch is a quiet cinema room with space for another person. The large serif
welcome and the actual film are the memorable elements; controls stay familiar
and touch friendly. Primary actions remain start, join, and open a video.

- Midnight navy `#10141F`: page and chrome.
- Slate `#1A2232`: raised controls and messages.
- Warm ivory `#F5EDE0`: readable primary text.
- Apricot `#EFB38C`: the main action, used sparingly.
- Lavender `#B9A9D3`: secondary social cues.
- DM Sans: controls and reading; DM Serif Display: short welcoming headlines.

Phone home presents the invitation first and recent sessions below. Tablet
home uses two purposeful columns; the tablet player keeps conversation beside
the video. Phone chat uses a keyboard-aware sheet. Landscape prioritizes the
video with legible compact controls. No invented viewing history or activity
metrics fill empty states.

This direction follows the brief's dark, cozy identity while avoiding gradients,
glass dashboards, decorative pills, and miniature desktop controls. Final visual
acceptance requires rendered phone, small phone, tablet and landscape evidence;
this document alone does not establish that acceptance.

The bundled DM Sans and DM Serif Display fonts come from the Google Fonts
repository under the SIL Open Font License. Their complete notices are included
beside each font in `assets/fonts/`.

The original paw-and-play mark is in `assets/brand/meowwatch.svg`. The 1024px
submission icon and Android density variants are reproducible with Node.js,
the `sharp` package, and `node tools/generate_brand.cjs`.
