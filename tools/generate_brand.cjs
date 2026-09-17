// Rebuild the approved vector artwork and its platform exports with Node.js + sharp.
// Editable final source: assets/brand/meowwatch.svg. Options are separate studies.
const path = require('node:path');
const fs = require('node:fs/promises');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const brand = 'assets/brand';
const res = 'android/app/src/main/res';
const palette = { navy: '#102A43', cream: '#FFF5DF', blue: '#5BA8F5' };
const adaptiveScale = 0.68;
const adaptiveOffset = Number(((1 - adaptiveScale) * 500).toFixed(3));
const outputFiles = [];

async function write(relative, data) {
  const file = path.join(root, relative);
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file, data);
  outputFiles.push(relative);
}

function svg(contents, size = 1024) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 1000 1000">\n${contents}\n</svg>\n`;
}

function background(radius = 0) {
  return `<rect width="1000" height="1000" rx="${radius}" fill="${palette.navy}"/>`;
}

function markFrom(source) {
  const match = source.match(/<g id="mark">([\s\S]*?)<\/g>/);
  assert.ok(match, 'The master must contain one self-contained mark group.');
  return match[1].trim();
}

function monochrome(mark) {
  return mark.replaceAll(palette.cream, '#FFFFFF').replaceAll(palette.blue, '#FFFFFF');
}

async function render(relative, source, size, opaque = false) {
  const image = sharp(Buffer.from(source)).resize(size, size);
  if (opaque) image.removeAlpha();
  const buffer = await image.png().toBuffer();
  await write(relative, buffer);
  return buffer;
}

function androidVector(mark) {
  const paths = [...mark.matchAll(/<path\b([^>]+)\/>/g)].map(([, raw]) => {
    const attributes = Object.fromEntries([...raw.matchAll(/([\w-]+)="([^"]*)"/g)].map(([, key, value]) => [key, value]));
    const result = [`android:pathData="${attributes.d}"`, `android:fillColor="${attributes.fill === 'none' ? '#00000000' : attributes.fill ?? '#00000000'}"`];
    for (const [svgName, androidName] of [['stroke', 'strokeColor'], ['stroke-width', 'strokeWidth'], ['stroke-linecap', 'strokeLineCap'], ['stroke-linejoin', 'strokeLineJoin']]) {
      if (attributes[svgName]) result.push(`android:${androidName}="${attributes[svgName]}"`);
    }
    return `        <path ${result.join('\n            ')}/>`;
  });
  assert.ok(paths.length > 0);
  return `<?xml version="1.0" encoding="utf-8"?>\n<vector xmlns:android="http://schemas.android.com/apk/res/android"\n    android:width="108dp" android:height="108dp"\n    android:viewportWidth="1000" android:viewportHeight="1000">\n    <group android:scaleX="${adaptiveScale}" android:scaleY="${adaptiveScale}"\n        android:translateX="${adaptiveOffset}" android:translateY="${adaptiveOffset}">\n${paths.join('\n')}\n    </group>\n</vector>\n`;
}

function ico(buffers) {
  const header = Buffer.alloc(6 + buffers.length * 16);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(buffers.length, 4);
  let offset = header.length;
  buffers.forEach(({ size, data }, index) => {
    const entry = 6 + index * 16;
    header[entry] = size === 256 ? 0 : size;
    header[entry + 1] = size === 256 ? 0 : size;
    header.writeUInt16LE(1, entry + 4);
    header.writeUInt16LE(32, entry + 6);
    header.writeUInt32LE(data.length, entry + 8);
    header.writeUInt32LE(offset, entry + 12);
    offset += data.length;
  });
  return Buffer.concat([header, ...buffers.map(item => item.data)]);
}

async function masked(mark, type, size = 160, adaptive = false) {
  const content = adaptive ? `<g transform="translate(${adaptiveOffset} ${adaptiveOffset}) scale(${adaptiveScale})">${mark}</g>` : mark;
  // AdaptiveIconDrawable's visible mask covers the middle 72 of 108 dp.
  const image = svg(`${background()}${content}`, 1000);
  const raster = await sharp(Buffer.from(image)).resize(1080).png().toBuffer();
  const viewport = adaptive
    ? await sharp(raster).extract({ left: 180, top: 180, width: 720, height: 720 }).resize(size).png().toBuffer()
    : await sharp(raster).resize(size).png().toBuffer();
  const mask = type === 'circle'
    ? `<circle cx="${size / 2}" cy="${size / 2}" r="${size / 2}" fill="white"/>`
    : `<rect width="${size}" height="${size}" rx="${size * .23}" fill="white"/>`;
  return sharp(viewport).composite([{ input: Buffer.from(`<svg width="${size}" height="${size}">${mask}</svg>`), blend: 'dest-in' }]).png().toBuffer();
}

async function contactSheet(options, small) {
  const width = 1440, height = 900;
  const labels = [
    ['A', 'Balanced · SELECTED', 'Faithful outline, cleaner ear corners'],
    ['B', 'Geometric', 'Straighter cheeks, firmer corners'],
    ['C', 'Compact', 'Tighter silhouette, heavier outline'],
  ];
  let text = `<svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg"><rect width="${width}" height="${height}" fill="#F5F1E8"/><g font-family="Arial, sans-serif" fill="${palette.navy}"><text x="64" y="64" font-size="30" font-weight="700">MeowWatch · final icon refinement</text><text x="64" y="96" font-size="16">Flat navy, cream and blue · the original cat-and-play composition</text>`;
  const composite = [];
  for (let i = 0; i < options.length; i++) {
    const x = 64 + i * 460;
    const [letter, title, description] = labels[i];
    text += `<text x="${x}" y="148" font-size="22" font-weight="700">${letter} / ${title}</text><text x="${x}" y="177" font-size="15">${description}</text>`;
    composite.push({ input: await masked(options[i], 'squircle', 310), left: x + 35, top: 202 });
    text += `<text x="${x}" y="552" font-size="16" font-weight="700">Actual pixel sizes</text>`;
    for (const [index, size] of [24, 32, 48].entries()) {
      composite.push({ input: await masked(options[i], 'squircle', size), left: x + index * 96, top: 578 + Math.floor((48 - size) / 2) });
      text += `<text x="${x + index * 96}" y="652" font-size="14">${size} px</text>`;
    }
    text += `<text x="${x}" y="697" font-size="16" font-weight="700">Android adaptive masks</text>`;
    composite.push({ input: await masked(options[i], 'circle', 112, true), left: x, top: 718 });
    composite.push({ input: await masked(options[i], 'squircle', 112, true), left: x + 134, top: 718 });
  }
  text += '<text x="64" y="872" font-size="14">Full-detail comparisons above. Dedicated 16–32 px simplified exports appear in the separate size-check sheet.</text></g></svg>';
  await write(`${brand}/icon-options.png`, await sharp(Buffer.from(text)).composite(composite).png().toBuffer());

  const detailLayers = [];
  let detail = `<svg width="1200" height="440" xmlns="http://www.w3.org/2000/svg"><rect width="1200" height="440" fill="#F5F1E8"/><g font-family="Arial, sans-serif" fill="${palette.navy}"><text x="48" y="55" font-size="26" font-weight="700">Selected A · platform checks</text>`;
  for (const [index, size] of [16, 24, 32, 48, 64, 128].entries()) {
    const x = 48 + index * 168;
    detailLayers.push({ input: await masked(size <= 32 ? small : options[0], 'squircle', size), left: x, top: 95 + Math.floor((128 - size) / 2) });
    detail += `<text x="${x}" y="250" font-size="15">${size} px${size <= 32 ? ' simplified' : ''}</text>`;
  }
  detail += `<text x="48" y="300" font-size="16">Monochrome / Android themed icon</text></g><rect x="183" y="330" width="80" height="80" rx="16" fill="${palette.navy}"/></svg>`;
  detailLayers.push({ input: await masked(monochrome(options[0]), 'circle', 96, true), left: 48, top: 322 });
  detailLayers.push({ input: await sharp(Buffer.from(svg(monochrome(small)))).resize(48).png().toBuffer(), left: 198, top: 346 });
  await write(`${brand}/icon-size-checks.png`, await sharp(Buffer.from(detail)).composite(detailLayers).png().toBuffer());
}

async function verifyAdaptive(foreground) {
  const { data, info } = await sharp(Buffer.from(foreground)).resize(1080).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  let maxRadius = 0, count = 0;
  for (let y = 0; y < info.height; y++) for (let x = 0; x < info.width; x++) {
    if (data[(y * info.width + x) * 4 + 3] > 16) {
      maxRadius = Math.max(maxRadius, Math.hypot(x + .5 - 540, y + .5 - 540));
      count++;
    }
  }
  assert.ok(count > 0, 'Adaptive foreground is empty.');
  assert.ok(maxRadius <= 330, `Foreground exceeds the 66 dp circular safe zone: ${maxRadius / 10} dp radius.`);
  return { canvasDp: 108, safeCircleDiameterDp: 66, actualRadiusDp: Number((maxRadius / 10).toFixed(3)), allVisiblePixelsInsideSafeCircle: true };
}

async function main() {
  const master = await fs.readFile(path.join(root, `${brand}/meowwatch.svg`), 'utf8');
  const mark = markFrom(master);
  const small = markFrom(await fs.readFile(path.join(root, `${brand}/meowwatch-small.svg`), 'utf8'));
  const optionB = markFrom(await fs.readFile(path.join(root, `${brand}/options/geometric.svg`), 'utf8'));
  const optionC = markFrom(await fs.readFile(path.join(root, `${brand}/options/compact.svg`), 'utf8'));
  for (const size of [256, 512, 1024]) await render(`${brand}/meowwatch-${size}.png`, master, size, true);
  await render(`${brand}/options/geometric-1024.png`, svg(`${background()}${optionB}`), 1024, true);
  await render(`${brand}/options/compact-1024.png`, svg(`${background()}${optionC}`), 1024, true);
  for (const size of [16, 24, 32, 48, 64, 128, 256]) {
    await render(`${brand}/png/meowwatch-${size}.png`, svg(`${background(210)}${size <= 32 ? small : mark}`), size);
  }
  const desktop = svg(`${background(210)}${mark}`);
  await write(`${brand}/meowwatch-desktop.svg`, desktop);
  await render(`${brand}/meowwatch-desktop-1024.png`, desktop, 1024);
  const iconBuffers = [];
  for (const size of [16, 24, 32, 48, 64, 128, 256]) {
    iconBuffers.push({ size, data: await sharp(Buffer.from(svg(`${background(210)}${size <= 32 ? small : mark}`))).resize(size).png().toBuffer() });
  }
  await write(`${brand}/meowwatch.ico`, ico(iconBuffers));
  const mono = svg(monochrome(mark));
  await write(`${brand}/meowwatch-monochrome.svg`, mono);
  await render(`${brand}/meowwatch-monochrome-1024.png`, mono, 1024);
  await write(`${brand}/meowwatch-small-monochrome.svg`, svg(monochrome(small)));
  await render(`${brand}/meowwatch-small-32.png`, svg(`${background(210)}${small}`), 32);
  const foreground = svg(`<g transform="translate(${adaptiveOffset} ${adaptiveOffset}) scale(${adaptiveScale})">${mark}</g>`);
  await write(`${brand}/android/foreground.svg`, foreground);
  await write(`${brand}/android/background.svg`, svg(background()));
  await write(`${brand}/android/monochrome.svg`, svg(`<g transform="translate(${adaptiveOffset} ${adaptiveOffset}) scale(${adaptiveScale})">${monochrome(mark)}</g>`));
  await render(`${brand}/android/foreground-432.png`, foreground, 432);
  await render(`${brand}/android/background-432.png`, svg(background()), 432, true);
  await write(`${res}/drawable/ic_launcher_foreground.xml`, androidVector(mark));
  await write(`${res}/drawable/ic_launcher_monochrome.xml`, androidVector(monochrome(mark)));
  await write(`${res}/values/icon_colors.xml`, `<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">${palette.navy}</color>\n</resources>\n`);
  for (const [qualifier, themed] of [['v26', false], ['v33', true]]) {
    await write(`${res}/mipmap-anydpi-${qualifier}/ic_launcher.xml`, `<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n    <background android:drawable="@color/ic_launcher_background"/>\n    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n${themed ? '    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>\n' : ''}</adaptive-icon>\n`);
  }
  for (const [density, size] of Object.entries({ mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 })) {
    await render(`${res}/mipmap-${density}/ic_launcher.png`, desktop, size);
  }
  await contactSheet([mark, optionB, optionC], small);
  const exports = [];
  for (const file of outputFiles.sort()) {
    const data = await fs.readFile(path.join(root, file));
    const record = { file, bytes: data.length, sha256: crypto.createHash('sha256').update(data).digest('hex') };
    if (file.endsWith('.png')) {
      const metadata = await sharp(data).metadata();
      record.width = metadata.width;
      record.height = metadata.height;
      record.hasAlpha = metadata.hasAlpha;
    }
    exports.push(record);
  }
  const inputs = [];
  for (const file of [`${brand}/meowwatch.svg`, `${brand}/meowwatch-small.svg`, `${brand}/options/geometric.svg`, `${brand}/options/compact.svg`, 'tools/generate_brand.cjs']) {
    const data = await fs.readFile(path.join(root, file));
    inputs.push({ file, sha256: crypto.createHash('sha256').update(data).digest('hex') });
  }
  const report = { selectedDirection: 'A / Balanced', renderer: { sharp: sharp.versions.sharp, libvips: sharp.versions.vips }, palette, adaptive: await verifyAdaptive(foreground), icoSizes: iconBuffers.map(item => item.size), inputs, exports };
  await write(`${brand}/exports.json`, `${JSON.stringify(report, null, 2)}\n`);
  console.log(`Exported ${outputFiles.length} files; adaptive foreground fits a 66 dp safe circle (${report.adaptive.actualRadiusDp} dp radius).`);
}

main().catch(error => { console.error(error); process.exitCode = 1; });
