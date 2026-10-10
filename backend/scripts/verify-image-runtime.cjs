// Run inside the actual Alpine build image. No network, database, or user data.
// This guards native ABI/codec compatibility separately from Ubuntu unit CI.
const assert = require('node:assert/strict');
const sharp = require('sharp');

async function main() {
  for (const format of ['png', 'jpeg', 'webp']) {
    const source = await sharp({ create: {
      width: 32, height: 16, channels: 4,
      background: { r: 0, g: 0, b: 255, alpha: 0.5 },
    } }).toFormat(format).toBuffer();
    const output = await sharp(source, { failOn: 'none' })
      .rotate().resize({ width: 16, withoutEnlargement: true, fit: 'inside' })
      .flatten({ background: { r: 255, g: 255, b: 255 } })
      .jpeg({ quality: 82, progressive: true, mozjpeg: true }).toBuffer();
    const metadata = await sharp(output).metadata();
    assert.equal(metadata.width, 16);
    assert.equal(metadata.height, 8);
    assert.equal(metadata.format, 'jpeg');
    assert.equal(metadata.isProgressive, true);
  }
  console.log(`Native image smoke passed: Node ${process.version}, sharp ${sharp.versions.sharp}, libvips ${sharp.versions.vips}; PNG/JPEG/WebP`);
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
