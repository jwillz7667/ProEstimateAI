#!/usr/bin/env node
// Validate the physical campaign, not just a generated filename/count fixture.
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('../backend/node_modules/sharp');
const root = path.resolve(__dirname, '..');
const campaign = path.resolve(process.argv[2] || path.join(root, 'artifacts/app-store-listing/2026-11-03'));
(async () => {
  const manifest = JSON.parse(await fs.readFile(path.join(campaign, 'manifest.json'), 'utf8'));
  if (manifest.panelCount !== 5 || manifest.families.length !== 6) throw new Error('Expected five panels across six export families');
  const expectedIds = ['iphone-dynamic-island-medium', 'iphone-dynamic-island-large', 'iphone-face-id-large', 'ipad-13', 'ipad-12-9', 'ipad-11'];
  if (JSON.stringify(manifest.families.map((f) => f.id)) !== JSON.stringify(expectedIds)) throw new Error('Unexpected device-family selection');
  const checks = [];
  for (const family of manifest.families) {
    if (family.files.length !== 5 || family.files.map((p) => path.basename(p).slice(0, 2)).join(',') !== '01,02,03,04,05') throw new Error(`Incorrect ordered panel count: ${family.id}`);
    if (family.virtualPanoramaWidth !== 5 * family.width + 4 * family.virtualGapWidth) throw new Error(`Incorrect gap canvas: ${family.id}`);
    if (Math.abs(family.virtualGapWidth - family.width * family.gapRatio) > .5) throw new Error(`Incorrect gutter calibration: ${family.id}`);
    for (const [index, file] of family.files.entries()) {
      if (family.cropOffsets[index] !== index * (family.width + family.virtualGapWidth)) throw new Error(`Incorrect gutter-aware crop offset: ${family.id}/${index}`);
      const absolute = await fs.realpath(path.join(campaign, file));
      if (!absolute.startsWith((await fs.realpath(campaign)) + path.sep)) throw new Error('Campaign file escapes its directory');
      const m = await sharp(absolute).metadata();
      if (m.width !== family.width || m.height !== family.height || m.hasAlpha || m.channels !== 3 || m.space !== 'srgb') throw new Error(`Incorrect dimensions/color format: ${file}`);
    }
    checks.push({ family: family.id, count: 5, dimensions: [family.width, family.height], virtualGapWidth: family.virtualGapWidth, cropOffsets: family.cropOffsets, rgbWithoutAlpha: true });
  }
  const proof = { checkedAt: new Date().toISOString(), filesChecked: 30, stagedLocaleCount: 5, stagedBucketsPerLocale: 5, stagedFilesExpected: 125, referenceGapRatio: manifest.background.referenceGapRatio, backdrop: 'Original curved orange ribbon with virtual gallery-gutter segments', freshRuntimeCapture: false, families: checks };
  await fs.writeFile(path.join(campaign, 'validation.json'), JSON.stringify(proof, null, 2) + '\n');
  console.log('30 exact-size RGB PNGs verified; five panels per export family; virtual-gap crop strides verified; 125 staged files expected.');
})().catch((error) => { console.error(error); process.exitCode = 1; });
