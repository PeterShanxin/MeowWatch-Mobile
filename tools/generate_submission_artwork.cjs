// Typeset the submission cover using the approved mark and bundled OFL fonts.
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const sharp = require('sharp');
const opentype = require('opentype.js');
const root = path.resolve(__dirname, '..');
const outputDirectory = 'assets/submission';
const baseName = 'meowwatch-devpost-1200x800';
const colors = { navy: '#102A43', cream: '#FFF5DF', blue: '#5BA8F5' };

function escapeXml(value) {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}

function parseFont(buffer) {
  return opentype.parse(buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength));
}

async function main() {
  const inputPaths = ['assets/brand/meowwatch.svg', 'assets/fonts/DMSans.ttf', 'assets/fonts/DMSerifDisplay.ttf', 'tools/generate_submission_artwork.cjs', 'assets/fonts/DMSans-OFL.txt', 'assets/fonts/DMSerifDisplay-OFL.txt'];
  const inputBuffers = await Promise.all(inputPaths.map(file => fs.readFile(path.join(root, file))));
  const [brandSource, sansBuffer, serifBuffer] = inputBuffers;
  const mark = brandSource.toString('utf8').match(/<g id="mark">([\s\S]*?)<\/g>/)?.[1];
  assert.ok(mark, 'Approved brand source must contain the mark group.');
  const fonts = { sans: parseFont(sansBuffer), serif: parseFont(serifBuffer) };
  const lines = [
    { text: 'MeowWatch', font: 'sans', size: 78, x: 540, y: 282, fill: colors.cream },
    { text: 'MOBILE', font: 'sans', size: 24, x: 545, y: 329, fill: colors.blue, tracking: 5 },
    { text: 'Movie night,', font: 'serif', size: 66, x: 540, y: 447, fill: colors.cream },
    { text: 'even when you’re', font: 'serif', size: 60, x: 540, y: 523, fill: colors.cream },
    { text: 'miles apart.', font: 'serif', size: 66, x: 540, y: 599, fill: colors.cream },
  ];
  const bounds = [];
  const outlineElements = lines.map(line => {
    const font = fonts[line.font];
    const options = { kerning: true, letterSpacing: (line.tracking ?? 0) / line.size };
    const glyphPath = font.getPath(line.text, line.x, line.y, line.size, options);
    const box = glyphPath.getBoundingBox();
    assert.ok(box.x1 >= 0 && box.y1 >= 0 && box.x2 <= 1136 && box.y2 <= 720, `Text overflows cover safe margins: ${line.text}`);
    bounds.push({ text: line.text, x1: box.x1, y1: box.y1, x2: box.x2, y2: box.y2 });
    return `<g aria-label="${escapeXml(line.text)}"><path fill="${line.fill}" d="${glyphPath.toPathData(3)}"/></g>`;
  });
  const textElements = lines.map(line => `<text x="${line.x}" y="${line.y}" font-family="${line.font === 'sans' ? 'MeowWatch DM Sans' : 'MeowWatch DM Serif'}" font-size="${line.size}"${line.tracking ? ` letter-spacing="${line.tracking}"` : ''} fill="${line.fill}">${escapeXml(line.text)}</text>`);
  const metadata = `<title id="title">MeowWatch Mobile</title>\n<desc id="description">Movie night, even when you’re miles apart. Selected A cat-and-play logo and typography, without product screenshots or feature claims.</desc>`;
  const composition = `<rect width="1200" height="800" fill="${colors.navy}"/>\n<g id="brand-mark" transform="translate(36 164) scale(.48)">${mark}</g>`;
  const wrap = (contents, definitions = '') => `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="800" viewBox="0 0 1200 800" role="img" aria-labelledby="title description">\n${metadata}\n${definitions}\n${composition}\n${contents}\n</svg>\n`;
  const outlined = wrap(outlineElements.join('\n'));
  const fontLicenses = inputBuffers.slice(4).map(buffer => buffer.toString('utf8')).join('\n\n');
  const fontDefinitions = `<metadata id="embedded-font-licenses">${escapeXml(fontLicenses)}</metadata>\n<defs><style>\n@font-face { font-family: 'MeowWatch DM Sans'; src: url('data:font/ttf;base64,${sansBuffer.toString('base64')}') format('truetype'); font-weight: 100 1000; }\n@font-face { font-family: 'MeowWatch DM Serif'; src: url('data:font/ttf;base64,${serifBuffer.toString('base64')}') format('truetype'); }\n</style></defs>`;
  const editable = wrap(textElements.join('\n'), fontDefinitions);
  const files = [
    { name: `${baseName}.svg`, buffer: Buffer.from(editable) },
    { name: `${baseName}-outlined.svg`, buffer: Buffer.from(outlined) },
    { name: `${baseName}.png`, buffer: await sharp(Buffer.from(outlined)).removeAlpha().png().toBuffer() },
  ];
  await fs.mkdir(path.join(root, outputDirectory), { recursive: true });
  for (const file of files) await fs.writeFile(path.join(root, outputDirectory, file.name), file.buffer);
  const pngMetadata = await sharp(files[2].buffer).metadata();
  assert.equal(pngMetadata.width, 1200);
  assert.equal(pngMetadata.height, 800);
  assert.equal(pngMetadata.hasAlpha, false);
  const sha256 = buffer => crypto.createHash('sha256').update(buffer).digest('hex');
  const manifest = {
    purpose: 'Devpost gallery thumbnail / project cover',
    width: 1200, height: 800, aspectRatio: '3:2',
    palette: colors,
    headline: 'MeowWatch Mobile',
    tagline: 'Movie night, even when you’re miles apart.',
    contentBoundary: 'Brand mark and tagline only; no UI screenshot, device claim, purchase claim or submission-acceptance claim.',
    renderer: { sharp: sharp.versions.sharp, libvips: sharp.versions.vips, opentype: '1.3.4' },
    fonts: [{ family: 'DM Sans', file: inputPaths[1], license: '../fonts/DMSans-OFL.txt' }, { family: 'DM Serif Display', file: inputPaths[2], license: '../fonts/DMSerifDisplay-OFL.txt' }],
    inputs: inputPaths.map((file, index) => ({ file, sha256: sha256(inputBuffers[index]) })),
    outputs: files.map(file => ({ file: `${outputDirectory}/${file.name}`, bytes: file.buffer.length, sha256: sha256(file.buffer) })),
    textBounds: bounds,
  };
  await fs.writeFile(path.join(root, outputDirectory, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(`Created ${baseName}: opaque 1200×800 PNG, editable embedded-font SVG and portable outlined SVG.`);
}

main().catch(error => { console.error(error); process.exitCode = 1; });
