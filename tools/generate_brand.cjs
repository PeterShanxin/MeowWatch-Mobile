// Rebuild the original vector mark with Node.js and the sharp package.
const path = require('node:path');
const fs = require('node:fs/promises');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'assets/brand/meowwatch.svg');

async function render(destination, size) {
  const file = path.join(root, destination);
  await fs.mkdir(path.dirname(file), { recursive: true });
  await sharp(source).resize(size, size).png().toFile(file);
}

async function main() {
  await render('assets/brand/meowwatch-1024.png', 1024);
  for (const [density, size] of Object.entries({ mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 })) {
    await render(`android/app/src/main/res/mipmap-${density}/ic_launcher.png`, size);
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
