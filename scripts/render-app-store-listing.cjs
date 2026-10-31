#!/usr/bin/env node
/**
 * Render an editable, continuous three-panel App Store campaign.
 * Install backend dependencies first; SVG carries layout, PNGs carry device art.
 * The image_gen cutouts are preserved; only layout/export is deterministic here.
 */
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('../backend/node_modules/sharp');

const root = path.resolve(__dirname, '..');
const output = path.resolve(process.argv[2] || path.join(root, 'artifacts/app-store-listing/2026-10-30'));
const families = [
  { id: 'iphone-dynamic-island-medium', width: 1206, height: 2622, required: true, device: 'iPhone Dynamic Island, medium display' },
  { id: 'iphone-dynamic-island-large', width: 1320, height: 2868, required: false, device: 'iPhone Dynamic Island, large display' },
  { id: 'iphone-face-id-large', width: 1284, height: 2778, required: false, device: 'iPhone Face ID, large display' },
  { id: 'ipad-13', width: 2064, height: 2752, required: true, device: 'iPad 13 inch', tablet: true },
  { id: 'ipad-12-9', width: 2048, height: 2732, required: false, device: 'iPad 12.9 inch', tablet: true },
  { id: 'ipad-11', width: 1668, height: 2420, required: false, device: 'iPad 11 inch', tablet: true },
];
const panels = [
  { slug: '01-photo-to-preview', title: ['See the vision.', 'Before you build.'], detail: ['Turn a job-site photo into', 'an AI remodel preview.'], phone: '01-preview-device.png', crop: [78, 52, 816, 1530], tablet: '01-ipad-preview.png' },
  { slug: '02-project-command-center', title: ['Every job.', 'One clear view.'], detail: ['Projects, clients, and next steps', 'come together in one place.'], phone: '02-dashboard-device.png', crop: [196, 111, 635, 1315], tablet: '02-ipad-dashboard.png' },
  { slug: '03-estimates-to-invoices', title: ['Clear quotes.', 'Confident next steps.'], detail: ['Build estimates, share proposals,', 'and track invoices.'], phone: '03-estimate-device.png', crop: [83, 126, 936, 1373], tablet: '03-ipad-project.png', tabletSlug: '03-project-details', tabletTitle: ['Every detail.', 'Ready when you are.'], tabletDetail: ['Keep the scope, budget, and photos', 'together for your next step.'] },
];
const xml = (text) => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');
const uri = async (file) => `data:image/png;base64,${(await fs.readFile(file)).toString('base64')}`;

function backdrop(width, height) {
  // One global coordinate system spans all three panels. Never restart it per panel.
  const full = width * 3;
  return `<defs>
    <linearGradient id="base" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#181818"/><stop offset=".5" stop-color="#080808"/><stop offset="1" stop-color="#202020"/></linearGradient>
    <linearGradient id="ribbon" x1="0" y1="0" x2="1" y2=".8"><stop stop-color="#ffb163"/><stop offset=".46" stop-color="#ff9230"/><stop offset="1" stop-color="#ce4b04"/></linearGradient>
    <linearGradient id="lower" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#ffb66d" stop-opacity=".25"/><stop offset="1" stop-color="#8e3300" stop-opacity="0"/></linearGradient>
    <filter id="device-shadow" x="-.3" y="-.2" width="1.6" height="1.5"><feDropShadow dx="0" dy="30" stdDeviation="30" flood-color="#000" flood-opacity=".65"/></filter>
  </defs>
  <rect width="${full}" height="${height}" fill="url(#base)"/>
  <path d="M ${-width*.2} ${height*.70} C ${width*.5} ${height*.16}, ${width*.85} ${height*.92}, ${width*1.43} ${height*.65} S ${width*2.25} ${height*.35}, ${full+width*.2} ${height*.67} L ${full+width*.2} ${height*1.15} L ${-width*.2} ${height*1.15} Z" fill="url(#ribbon)"/>
  <path d="M ${-width*.2} ${height*.84} C ${width*.5} ${height*.32}, ${width*.85} ${height*1.07}, ${width*1.43} ${height*.80} S ${width*2.25} ${height*.50}, ${full+width*.2} ${height*.82} L ${full+width*.2} ${height*1.15} L ${-width*.2} ${height*1.15} Z" fill="url(#lower)"/>
  <path d="M ${-width*.2} ${height*.70} C ${width*.5} ${height*.16}, ${width*.85} ${height*.92}, ${width*1.43} ${height*.65} S ${width*2.25} ${height*.35}, ${full+width*.2} ${height*.67}" fill="none" stroke="#ffc080" stroke-opacity=".6" stroke-width="2"/>`;
}

async function makePanel(panel, index, family, icon) {
  const { width: w, height: h, tablet } = family;
  const x = index * w;
  const scale = w / 1320;
  const font = "Arial, Helvetica, sans-serif";
  const title = tablet && panel.tabletTitle ? panel.tabletTitle : panel.title;
  const detail = tablet && panel.tabletDetail ? panel.tabletDetail : panel.detail;
  const margin = w * .075;
  const headerY = h * .032;
  const badgeH = tablet ? h * .046 : 108 * scale;
  const badgeW = tablet ? w * .41 : 672 * scale;
  const brandFont = tablet ? w * .0295 : 48 * scale;
  const titleSize = tablet ? w * .062 : (index === 2 ? 102 : 112) * scale;
  const firstY = tablet ? h * .151 : h * .132;
  const lineGap = titleSize * 1.08;
  const detailSize = tablet ? w * .025 : 39 * scale;
  const detailY = firstY + lineGap + detailSize * 1.7;
  const asset = path.join(output, 'assets', tablet ? panel.tablet : panel.phone);
  const art = await uri(asset);
  const metadata = await sharp(asset).metadata();
  const top = tablet ? h * .385 : h * .286;
  const maxHeight = h - top - h * .018;
  const maxWidth = tablet ? w * .91 : w * .98;
  const crop = tablet ? [0, 0, metadata.width, metadata.height] : panel.crop;
  const factor = Math.min(maxWidth / crop[2], maxHeight / crop[3]);
  const deviceW = Math.round(crop[2] * factor);
  const deviceH = Math.round(crop[3] * factor);
  const deviceX = (w - deviceW) / 2;
  const pad = tablet ? w * .012 : 0;
  const frame = tablet ? `<rect x="${deviceX-pad}" y="${top-pad}" width="${deviceW+pad*2}" height="${deviceH+pad*2}" rx="${w*.023}" fill="#090909" stroke="#626262" stroke-width="${w*.0015}"/><defs><clipPath id="tablet-clip-${index}"><rect x="${deviceX}" y="${top}" width="${deviceW}" height="${deviceH}" rx="${w*.016}"/></clipPath></defs>` : '';
  const deviceArt = `<svg x="${deviceX}" y="${top}" width="${deviceW}" height="${deviceH}" viewBox="${crop.join(' ')}"><image href="${art}" x="0" y="0" width="${metadata.width}" height="${metadata.height}"/></svg>`;
  return `<g transform="translate(${x} 0)" font-family="${font}">
    <g id="brand-${index}">
      <rect x="${margin}" y="${headerY}" width="${badgeW}" height="${badgeH}" rx="${badgeH*.30}" fill="#121212" stroke="#6d6d6d" stroke-width="1.5"/>
      <image href="${icon}" x="${margin+badgeH*.14}" y="${headerY+badgeH*.13}" width="${badgeH*.74}" height="${badgeH*.74}"/>
      <text x="${margin+badgeH*1.04}" y="${headerY+badgeH*.665}" font-size="${brandFont}" font-weight="700" fill="#fff">ProEstimate <tspan fill="#ff9230">AI</tspan></text>
    </g>
    <text x="${margin}" y="${firstY}" font-size="${titleSize}" font-weight="800" letter-spacing="${-titleSize*.035}" fill="#fff">${xml(title[0])}</text>
    <text x="${margin}" y="${firstY+lineGap}" font-size="${titleSize}" font-weight="800" letter-spacing="${-titleSize*.035}" fill="#ffad61">${xml(title[1])}</text>
    <text x="${margin}" y="${detailY}" font-size="${detailSize}" fill="#e3e3e6">${xml(detail[0])}<tspan x="${margin}" dy="${detailSize*1.30}">${xml(detail[1])}</tspan></text>
    <g filter="url(#device-shadow)">${frame}${tablet ? `<g clip-path="url(#tablet-clip-${index})">${deviceArt}</g>` : deviceArt}</g>
  </g>`;
}

(async () => {
  await fs.mkdir(output, { recursive: true });
  const icon = await uri(path.join(root, 'ProEstimate AI/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Default-1024x1024@1x.png'));
  const manifest = { generatedAt: new Date().toISOString(), language: 'en-US', source: 'https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications', note: 'Marketing concepts. iPhone device art is AI generated; replace with final approved captures before submission. iPad sources are recorded separately. Background is a single continuous SVG, sliced in order 01→02→03. PNGs use sRGB, RGB without alpha.', families: [] };
  for (const family of families) {
    if (family.tablet && !(await fs.stat(path.join(output, 'assets', panels[0].tablet)).catch(() => null))) continue;
    const dir = path.join(output, family.id);
    await fs.mkdir(dir, { recursive: true });
    const foreground = await Promise.all(panels.map((p, i) => makePanel(p, i, family, icon)));
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${family.width*3}" height="${family.height}" viewBox="0 0 ${family.width*3} ${family.height}">${backdrop(family.width, family.height)}${foreground.join('')}</svg>`;
    const panorama = await sharp(Buffer.from(svg), { limitInputPixels: 100000000 }).flatten({ background: '#101010' }).removeAlpha().toColourspace('srgb').png().toBuffer();
    if (family.id === 'iphone-dynamic-island-large' || family.id === 'ipad-13') {
      await fs.writeFile(path.join(output, `${family.tablet ? 'ipad' : 'iphone'}-editable-panorama.svg`), svg);
      await sharp(panorama).resize({ width: family.tablet ? 1800 : 1500 }).png().toFile(path.join(output, `${family.tablet ? 'ipad' : 'iphone'}-side-by-side.png`));
    }
    const files = [];
    for (const [index, panel] of panels.entries()) {
      const name = `${family.tablet && panel.tabletSlug ? panel.tabletSlug : panel.slug}_${family.width}x${family.height}.png`;
      const file = path.join(dir, name);
      await sharp(panorama).extract({ left: index*family.width, top: 0, width: family.width, height: family.height }).removeAlpha().png().toFile(file);
      const meta = await sharp(file).metadata();
      if (meta.width !== family.width || meta.height !== family.height || meta.hasAlpha) throw new Error(`Invalid App Store export: ${file}`);
      files.push(`${family.id}/${name}`);
    }
    manifest.families.push({ ...family, files });
    console.log(`${family.id}: ${family.width} × ${family.height}, 3 RGB PNGs`);
  }
  await fs.writeFile(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2)+'\n');
})().catch((error) => { console.error(error); process.exitCode = 1; });
