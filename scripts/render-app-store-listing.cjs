#!/usr/bin/env node
/**
 * Render the original orange-ribbon campaign across five panels.
 * The full panorama includes virtual gallery gutters, then each screenshot is
 * sampled at index * (panelWidth + gapWidth). Original colors/curves are retained. Device illustrations
 * and historic capture crops are identified in manifest.json and sources.json.
 */
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require('../backend/node_modules/sharp');
const root = path.resolve(__dirname, '..');
const output = path.resolve(process.argv.slice(2).find((arg) => !arg.startsWith('--')) || path.join(root, 'artifacts/app-store-listing/2026-11-03'));
const requestedGapRatio = process.argv.find((arg) => arg.startsWith('--gap-ratio='))?.split('=')[1];
const prior = path.join(root, 'artifacts/app-store-listing/2026-10-30/assets');
const palette = { orange: '#FF9230', charcoal: '#1C1C1E', ink: '#0B0B0C', white: '#FFFFFF', secondary: '#C9C9CF' };
const families = [
  { id: 'iphone-dynamic-island-medium', width: 1206, height: 2622, required: true, device: 'iPhone Dynamic Island, medium display' },
  { id: 'iphone-dynamic-island-large', width: 1320, height: 2868, required: false, device: 'iPhone Dynamic Island, large display' },
  { id: 'iphone-face-id-large', width: 1284, height: 2778, required: false, device: 'iPhone Face ID, large display' },
  { id: 'ipad-13', width: 2064, height: 2752, required: true, device: 'iPad 13 inch', tablet: true },
  { id: 'ipad-12-9', width: 2048, height: 2732, required: false, device: 'iPad 12.9 inch', tablet: true },
  { id: 'ipad-11', width: 1668, height: 2420, required: false, device: 'iPad 11 inch', tablet: true },
];
const panels = [
  { slug: '01-photo-to-preview', title: ['See the vision.', 'Before you build.'], detail: ['Explore a remodel from a job-site photo.', 'Compare the original with your AI preview.'], subject: 'AI remodel comparison', provenance: 'Actual isolated-QA source and completed app generation, composed with an illustrative comparison control and device frame.' },
  { slug: '02-project-command-center', title: ['Every job.', 'One clear view.'], detail: ['Projects, clients and next steps', 'come together in one place.'], subject: 'Project-first Home', provenance: 'Code-derived illustration of the redesigned Home hierarchy with fictional sample data. Not a simulator/device capture.' },
  { slug: '03-estimates-to-invoices', title: ['Clear quotes.', 'Confident next steps.'], detail: ['Build estimates, share proposals', 'and track invoices.'], subject: 'Proposals and invoices', provenance: 'Previously selected generated iPhone marketing device art; iPad uses a code-native proposal illustration. Example data, not newly captured UI.' },
  { slug: '04-price-the-work', title: ['Price the work.', 'Your way.'], detail: ['Review materials, labor and quantities.', 'Adjust the numbers before you share.'], subject: 'Estimate materials and labor', provenance: 'iPhone uses an actual historic materials-list capture crop. iPad is a code-native estimate illustration with fictional sample values, not a fresh runtime capture.' },
  { slug: '05-projects-in-order', title: ['Every project.', 'Details in order.'], detail: ['Keep scope, photos and client details', 'together as the job moves forward.'], subject: 'Projects and scope', provenance: 'Existing actual project-list / project-detail capture crops. Historic navigation bars and the QA-only description are excluded by cropping. iPad metadata/photo composition and device framing are illustrative.' },
];
const xml = (s) => String(s).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');
const dataURI = async (file) => `data:${path.extname(file) === '.jpg' ? 'image/jpeg' : 'image/png'};base64,${(await fs.readFile(file)).toString('base64')}`;
const font = 'Arial, Helvetica, sans-serif';
const text = (x, y, value, size, fill = '#FFFFFF', weight = 400, extra = '') => `<text x="${x}" y="${y}" font-family="${font}" font-size="${size}" font-weight="${weight}" fill="${fill}" ${extra}>${xml(value)}</text>`;
const rect = (x, y, w, h, radius = 0, fill = '#1C1C1E', stroke = 'none', strokeWidth = 1) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${radius}" fill="${fill}" stroke="${stroke}" stroke-width="${strokeWidth}"/>`;
const photo = (uri, x, y, w, h, fit = 'xMidYMid slice') => `<image href="${uri}" x="${x}" y="${y}" width="${w}" height="${h}" preserveAspectRatio="${fit}"/>`;
const nested = (svg, viewWidth, viewHeight, x, y, w, h) => `<svg x="${x}" y="${y}" width="${w}" height="${h}" viewBox="0 0 ${viewWidth} ${viewHeight}">${svg}</svg>`;

function backdrop(virtualWidth, height) {
  // Original three-panel curve profile, expanded across the five-panel virtual
  // canvas INCLUDING the gallery gaps. Hidden strips are removed on export.
  const width = virtualWidth / 3;
  const full = virtualWidth;
  return `<defs>
    <linearGradient id="base" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#181818"/><stop offset=".5" stop-color="#080808"/><stop offset="1" stop-color="#202020"/></linearGradient>
    <linearGradient id="ribbon" x1="0" y1="0" x2="1" y2=".8"><stop stop-color="#ffb163"/><stop offset=".46" stop-color="#ff9230"/><stop offset="1" stop-color="#ce4b04"/></linearGradient>
    <linearGradient id="lower" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#ffb66d" stop-opacity=".25"/><stop offset="1" stop-color="#8e3300" stop-opacity="0"/></linearGradient>
    <filter id="shadow" x="-.3" y="-.2" width="1.6" height="1.5"><feDropShadow dx="0" dy="30" stdDeviation="30" flood-color="#000" flood-opacity=".65"/></filter>
  </defs>
  <rect width="${full}" height="${height}" fill="url(#base)"/>
  <path d="M ${-width*.2} ${height*.70} C ${width*.5} ${height*.16}, ${width*.85} ${height*.92}, ${width*1.43} ${height*.65} S ${width*2.25} ${height*.35}, ${full+width*.2} ${height*.67} L ${full+width*.2} ${height*1.15} L ${-width*.2} ${height*1.15} Z" fill="url(#ribbon)"/>
  <path d="M ${-width*.2} ${height*.84} C ${width*.5} ${height*.32}, ${width*.85} ${height*1.07}, ${width*1.43} ${height*.80} S ${width*2.25} ${height*.50}, ${full+width*.2} ${height*.82} L ${full+width*.2} ${height*1.15} L ${-width*.2} ${height*1.15} Z" fill="url(#lower)"/>
  <path d="M ${-width*.2} ${height*.70} C ${width*.5} ${height*.16}, ${width*.85} ${height*.92}, ${width*1.43} ${height*.65} S ${width*2.25} ${height*.35}, ${full+width*.2} ${height*.67}" fill="none" stroke="#ffc080" stroke-opacity=".6" stroke-width="2"/>`;
}

function phoneFrame(content, id) {
  return `${rect(0, 0, 430, 900, 60, '#080809', '#737379', 3)}${rect(8, 8, 414, 884, 54, '#1C1C1E', '#28282D', 1)}<defs><clipPath id="screen-${id}">${rect(18, 18, 394, 864, 45)}</clipPath></defs><g clip-path="url(#screen-${id})">${rect(18, 18, 394, 864, 45, '#000')}${nested(content, 390, 844, 20, 20, 390, 844)}</g>${rect(155, 29, 120, 32, 17, '#000')}${text(42, 50, '9:41', 15, '#fff', 700)}${text(344, 50, '▰', 17, '#fff')}${rect(166, 867, 98, 5, 3, '#F6F6F8')}`;
}
function tabletFrame(content, vw, vh, id) {
  return `${rect(0, 0, vw + 34, vh + 34, 35, '#070708', '#68686E', 2)}<defs><clipPath id="tablet-${id}">${rect(17, 17, vw, vh, 22)}</clipPath></defs><g clip-path="url(#tablet-${id})">${nested(content, vw, vh, 17, 17, vw, vh)}</g>`;
}
function tabBar(w, y) {
  const names = ['Home', 'Projects', 'Invoices', 'Clients', 'Settings'];
  return `${rect(10, y, w - 20, 58, 24, '#242426', '#45454A')}${names.map((s, i) => { const x = 10 + (w - 20) * (i + .5) / 5; return `${text(x, y + 25, ['⌂', '▣', '▤', '♙', '⚙'][i], 19, i === 0 ? palette.orange : '#DDDDE1', 600, 'text-anchor="middle"')}${text(x, y + 44, s, 9, i === 0 ? palette.orange : '#DDDDE1', 600, 'text-anchor="middle"')}`; }).join('')}`;
}
function homeScreen(tablet, assets) {
  const w = tablet ? 1000 : 390; const h = tablet ? 1280 : 844;
  const p = tablet ? 46 : 20;
  let s = rect(0, 0, w, h, 0, '#000');
  if (tablet) s += text(p, 40, '9:41', 17, '#fff', 600);
  s += text(p, tablet ? 123 : 105, 'Home', tablet ? 64 : 35, '#FFF', 700);
  s += `<circle cx="${w - p - 18}" cy="${tablet ? 97 : 87}" r="${tablet ? 23 : 17}" fill="#36291E"/>${text(w - p - 18, tablet ? 104 : 92, 'AM', tablet ? 15 : 11, palette.orange, 700, 'text-anchor="middle"')}`;
  s += text(p, tablet ? 172 : 143, 'Good morning, Alex', tablet ? 28 : 19, '#FFF', 600);
  s += text(p, tablet ? 201 : 165, 'Summit Remodeling', tablet ? 20 : 12, '#A5A5AD');
  const cy = tablet ? 230 : 187, cw = w - p * 2, ch = tablet ? 115 : 83;
  s += rect(p, cy, cw, ch, tablet ? 24 : 18, palette.orange);
  s += text(p + (tablet ? 31 : 20), cy + (tablet ? 48 : 35), '+', tablet ? 40 : 28, '#1C1C1E', 500);
  s += text(p + (tablet ? 88 : 55), cy + (tablet ? 46 : 33), 'New project', tablet ? 29 : 20, '#1C1C1E', 700);
  if (tablet) {
    s += text(p + 88, cy + 78, 'Keep photos, estimates and client details together.', 20, '#382313');
  } else {
    s += text(p + 55, cy + 55, 'Photos, estimates and client details', 10, '#382313');
    s += text(p + 55, cy + 69, 'together in one place.', 10, '#382313');
  }
  const ry = tablet ? 402 : 315;
  const recentW = tablet ? 560 : w - p * 2;
  s += text(p, ry, 'Recent projects', tablet ? 27 : 21, '#FFF', 700);
  s += text(p + recentW, ry, 'View all', tablet ? 18 : 12, palette.orange, 500, 'text-anchor="end"');
  const rows = [ ['Modern Kitchen Remodel', 'Kitchen', 'Draft', assets.after], ['Oak Street bath', 'Bathroom', 'Estimate ready', assets.bath], ['Garden patio', 'Patio', 'Preview ready', assets.patio] ];
  rows.forEach((r, i) => {
    const y = ry + (tablet ? 32 : 20) + i * (tablet ? 143 : 91); const rh = tablet ? 126 : 80;
    s += rect(p, y, recentW, rh, tablet ? 20 : 16, '#1C1C1E', '#48413A', 1);
    const tw = tablet ? 106 : 64, th = tablet ? 100 : 60;
    s += `<defs><clipPath id="thumb-${tablet}-${i}">${rect(p + 12, y + 10, tw, th, 10)}</clipPath></defs><g clip-path="url(#thumb-${tablet}-${i})">${photo(r[3], p + 12, y + 10, tw, th)}</g>`;
    const tx = p + tw + 26;
    s += text(tx, y + (tablet ? 39 : 26), r[0], tablet ? 23 : 15, '#FFF', 600);
    s += text(tx, y + (tablet ? 69 : 45), r[1], tablet ? 17 : 11, '#B6B6BE');
    s += text(tx, y + (tablet ? 101 : 65), r[2], tablet ? 16 : 10, palette.orange, 500);
    s += text(p + recentW - 18, y + (tablet ? 100 : 65), ['Nov 3', 'Nov 2', 'Nov 1'][i], tablet ? 14 : 9, '#B6B6BE', 400, 'text-anchor="end"');
    s += text(p + recentW - 17, y + rh / 2 + 5, '›', tablet ? 30 : 22, '#BBBBBF');
  });
  const mx = tablet ? 643 : p, my = tablet ? ry : 661, mw = tablet ? 311 : w - p * 2;
  s += text(mx, my, 'At a glance', tablet ? 25 : 19, '#FFF', 700);
  s += rect(mx, my + 20, mw, tablet ? 291 : 99, 18, '#1C1C1E', '#48413A', 1);
  const ms = [['Revenue this month', '$24,750'], ['Active projects', '7'], ['Invoices due', '2']];
  ms.forEach((r, i) => {
    const x = tablet ? mx + 22 : mx + 13 + i * ((mw - 26) / 3); const y = tablet ? my + 58 + i * 83 : my + 47;
    s += text(x, y, tablet ? r[0] : ['Revenue', 'Active jobs', 'Invoices due'][i], tablet ? 16 : 10, '#B6B6BE');
    s += text(x, y + (tablet ? 35 : 30), r[1], tablet ? 27 : 22, '#FFF', 650);
  });
  const py = tablet ? my + 355 : 811;
  if (tablet) {
    s += rect(mx, py, mw, 105, 18, '#1C1C1E', '#48413A', 1);
    s += text(mx + 22, py + 39, 'AI tools with Pro', 21, '#FFF', 650);
    s += text(mx + 22, py + 72, 'View Pro plans  ›', 17, palette.orange);
  }
  s += tabBar(w, tablet ? h - 85 : 786);
  return { content: s, w, h };
}
function previewScreen(assets, tablet) {
  const w = tablet ? 1200 : 390, h = tablet ? 950 : 844; const p = tablet ? 48 : 20;
  let s = rect(0, 0, w, h, 0, '#000');
  s += text(p, tablet ? 75 : 103, '‹', tablet ? 50 : 30, palette.orange);
  s += text(w / 2, tablet ? 77 : 102, 'Kitchen refresh', tablet ? 34 : 20, '#FFF', 650, 'text-anchor="middle"');
  s += text(p, tablet ? 154 : 163, 'AI Preview', tablet ? 36 : 24, '#FFF', 700);
  const iy = tablet ? 190 : 190, iw = w - p * 2, ih = tablet ? 640 : 422;
  s += `<defs><clipPath id="comparison">${rect(p, iy, iw, ih, 22)}</clipPath><clipPath id="after-half"><rect x="${p + iw / 2}" y="${iy}" width="${iw / 2}" height="${ih}"/></clipPath></defs><g clip-path="url(#comparison)">${photo(assets.before, p, iy, iw, ih)}<g clip-path="url(#after-half)">${photo(assets.after, p, iy, iw, ih)}</g></g>`;
  s += `<path d="M${w / 2} ${iy}V${iy + ih}" stroke="#FFF" stroke-width="${tablet ? 3 : 2}"/><circle cx="${w / 2}" cy="${iy + ih / 2}" r="${tablet ? 29 : 20}" fill="#FFF"/>${text(w / 2, iy + ih / 2 + (tablet ? 10 : 7), '‹ ›', tablet ? 28 : 20, '#3C3C42', 500, 'text-anchor="middle"')}`;
  s += rect(p + 14, iy + 16, tablet ? 97 : 65, tablet ? 43 : 29, 18, '#000000B3');
  s += text(p + (tablet ? 62 : 46), iy + (tablet ? 45 : 36), 'Before', tablet ? 21 : 13, '#FFF', 600, 'text-anchor="middle"');
  s += rect(w - p - (tablet ? 110 : 76), iy + 16, tablet ? 97 : 65, tablet ? 43 : 29, 18, '#000000B3');
  s += text(w - p - (tablet ? 61 : 43), iy + (tablet ? 45 : 36), 'After', tablet ? 21 : 13, '#FFF', 600, 'text-anchor="middle"');
  s += text(w / 2, iy + ih + (tablet ? 54 : 38), 'Drag to compare', tablet ? 23 : 14, '#B6B6BE', 400, 'text-anchor="middle"');
  if (!tablet) {
    s += rect(p, 699, iw, 62, 16, '#1C1C1E', '#48413A');
    s += text(p + 18, 725, 'A new direction for the same space', 13, '#FFF', 600);
    s += text(p + 18, 747, 'Forest-green cabinetry · warm brass', 11, '#B6B6BE');
  }
  return { content: s, w, h };
}
function proposalScreen() {
  const w = 1100, h = 1370;
  let s = rect(0, 0, w, h, 0, '#F9F9FA');
  s += rect(0, 0, w, 100, 0, '#141416');
  s += text(40, 64, '‹  Kitchen refresh', 30, '#FFF', 600);
  s += text(w - 42, 64, 'Share  ↗', 23, palette.orange, 500, 'text-anchor="end"');
  s += text(66, 185, 'SUMMIT REMODELING', 22, '#50505A', 650);
  s += text(w - 66, 188, 'ESTIMATE', 34, '#2A323A', 700, 'text-anchor="end"');
  s += text(66, 250, 'Kitchen refresh', 47, '#1C1C1E', 700);
  s += text(66, 294, 'Prepared for Alex Morgan', 23, '#62626B');
  s += `<path d="M66 336H1034" stroke="#FF9230" stroke-width="5"/>`;
  const rows = [['Cabinetry and hardware', '$4,200.00'], ['Countertops', '$2,600.00'], ['Fixtures and finishing', '$750.00'], ['Materials subtotal', '$7,550.00'], ['Preparation and installation', '$3,100.00'], ['Labor subtotal', '$3,100.00']];
  rows.forEach((r, i) => { const y = 414 + i * 94; s += text(66, y, r[0], 25, '#2A323A', i === 3 || i === 5 ? 650 : 400); s += text(w - 66, y, r[1], 26, '#2A323A', 600, 'text-anchor="end"'); s += `<path d="M66 ${y + 31}H1034" stroke="#DDDDE3" stroke-width="1"/>`; });
  s += rect(66, 1010, 968, 131, 16, '#FFF0E3');
  s += text(93, 1062, 'Estimated total', 26, '#2A323A', 600);
  s += text(1008, 1098, '$10,650.00', 51, '#1C1C1E', 700, 'text-anchor="end"');
  s += text(66, 1210, 'Scope, terms and next steps in one clear proposal.', 22, '#62626B');
  s += text(66, 1252, 'Example project • Review quantities and pricing before sharing.', 18, '#62626B');
  return { content: s, w, h };
}
async function projectArt(tablet, assets) {
  if (tablet) {
    let s = rect(0, 0, 1000, 1250, 0, '#000');
    s += text(42, 74, '‹', 42, palette.orange) + text(500, 73, 'Maple House Kitchen', 31, '#FFF', 650, 'text-anchor="middle"');
    s += text(42, 155, 'Project details', 43, '#FFF', 700);
    s += rect(42, 195, 916, 285, 20, '#1C1C1E', '#6B4D32');
    s += photo(assets.projectTablet, 52, 201, 896, 272, 'xMidYMid meet');
    s += text(42, 546, 'Project photos', 32, '#FFF', 650);
    s += `<defs><clipPath id="project-photo">${rect(42, 580, 916, 610, 22)}</clipPath></defs><g clip-path="url(#project-photo)">${photo(assets.before, 42, 580, 916, 610)}</g>`;
    return { content: s, w: 1000, h: 1250 };
  }
  return { content: `${rect(0, 0, 390, 844, 0, '#000')}${photo(assets.projects, 0, 78, 390, 704, 'xMidYMin meet')}`, w: 390, h: 844 };
}
function materialArt(tablet, assets) {
  if (!tablet) return { content: `${rect(0, 0, 390, 844, 0, '#000')}${text(20, 107, 'Materials', 29, '#FFF', 700)}${photo(assets.materials, 10, 130, 370, 643, 'xMidYMin meet')}${text(25, 725, 'Review quantities and rates', 14, '#FFF', 600)}${text(25, 750, 'Set final pricing for your project.', 11, '#B6B6BE')}`, w: 390, h: 844 };
  const w = 1200, h = 1060;
  let s = rect(0, 0, w, h, 0, '#000') + text(42, 75, 'Kitchen refresh', 34, '#FFF', 650) + text(42, 139, 'Estimate', 44, '#FFF', 700);
  s += text(43, 192, 'Review every quantity, rate and line item.', 24, '#B6B6BE');
  const rows = [['Materials', 'Cabinetry and hardware', '1 allowance', '$4,200.00'], ['', 'Quartz countertops', '65 sq ft × $40.00', '$2,600.00'], ['', 'Fixtures and finishing', '1 allowance', '$750.00'], ['Labor', 'Preparation and installation', '40 hours × $77.50', '$3,100.00']];
  rows.forEach((r, i) => { const y = 248 + i * 163; if (r[0]) s += text(42, y - 8, r[0], 23, palette.orange, 650); s += rect(42, y + 11, 1116, 121, 21, '#1C1C1E', '#48413A'); s += text(66, y + 55, r[1], 27, '#FFF', 600) + text(66, y + 99, r[2], 22, '#B6B6BE') + text(1128, y + 80, r[3], 28, '#FFF', 600, 'text-anchor="end"'); });
  s += rect(42, 930, 1116, 75, 18, palette.orange) + text(600, 978, 'Review estimate', 27, '#1C1C1E', 700, 'text-anchor="middle"');
  return { content: s, w, h };
}
async function loadAssets() {
  const cropped = async (file, region) => `data:image/png;base64,${(await sharp(file).extract(region).png().toBuffer()).toString('base64')}`;
  return {
    before: await dataURI(path.join(root, 'operations/validation-2026-10-30/comparison-source.jpg')),
    after: await dataURI(path.join(root, 'operations/validation-2026-10-30/comparison-complete-photo.png')),
    bath: await dataURI(path.join(root, 'ProEstimate AI/Assets.xcassets/CategoryThumbs/02_luxury_bathroom.imageset/02_luxury_bathroom.jpg')),
    patio: await dataURI(path.join(root, 'ProEstimate AI/Assets.xcassets/CategoryThumbs/36_outdoor_patio.imageset/36_outdoor_patio.jpg')),
    projects: await cropped(path.join(root, 'web/public/screenshots/projects.jpg'), { left: 0, top: 68, width: 441, height: 770 }),
    materials: await cropped(path.join(root, 'web/public/screenshots/materials.jpg'), { left: 0, top: 147, width: 441, height: 641 }),
    projectTablet: await cropped(path.join(prior, '03-ipad-project.png'), { left: 32, top: 560, width: 1320, height: 400 }),
    quoteDevice: await dataURI(path.join(prior, '03-estimate-device.png')),
  };
}
async function makePanel(panel, index, family, icon, assets, offset) {
  const w = family.width, h = family.height, tablet = !!family.tablet;
  const m = w * .075, badgeH = h * .038, brandSize = w * .036;
  const titleSize = w * (tablet ? .067 : .078), lineGap = titleSize * 1.10;
  const firstY = h * .141, detailSize = w * (tablet ? .029 : .031), detailY = firstY + lineGap + detailSize * 1.65;
  let s = "";
  s += rect(m, h * .035, w * .52, badgeH, badgeH * .28, '#151517', '#69696F', 1.4);
  s += photo(icon, m + badgeH * .13, h * .035 + badgeH * .13, badgeH * .74, badgeH * .74, 'xMidYMid meet');
  s += `<text x="${m + badgeH * 1.06}" y="${h * .035 + badgeH * .665}" font-family="${font}" font-size="${brandSize}" font-weight="700" fill="#FFF">ProEstimate <tspan fill="${palette.orange}">AI</tspan></text>`;
  s += text(w - m, h * .035 + badgeH * .665, `${String(index + 1).padStart(2, '0')} / 05`, w * .024, '#C7C7CC', 500, 'text-anchor="end"');
  s += text(m, firstY, panel.title[0], titleSize, '#FFF', 750, `letter-spacing="${-titleSize * .035}"`);
  s += text(m, firstY + lineGap, panel.title[1], titleSize, '#FFB06A', 750, `letter-spacing="${-titleSize * .035}"`);
  s += text(m, detailY, panel.detail[0], detailSize, '#ECECEE');
  s += text(m, detailY + detailSize * 1.4, panel.detail[1], detailSize, '#ECECEE');
  let art;
  if (index === 0) art = previewScreen(assets, tablet);
  else if (index === 1) art = homeScreen(tablet, assets);
  else if (index === 2 && tablet) art = proposalScreen();
  else if (index === 4) art = await projectArt(tablet, assets);
  else if (index === 3) art = materialArt(tablet, assets);

  const top = h * .31, maxH = h * .655, maxW = w * (tablet ? .88 : .80);
  if (index === 2 && !tablet) {
    const crop = [83, 126, 936, 1373], factor = Math.min(w * .94 / crop[2], maxH / crop[3]);
    const dw = crop[2] * factor, dh = crop[3] * factor;
    s += `<g filter="url(#shadow)"><svg x="${(w - dw) / 2}" y="${top + (maxH - dh) * .25}" width="${dw}" height="${dh}" viewBox="${crop.join(' ')}">${photo(assets.quoteDevice, 0, 0, 1024, 1536, 'none')}</svg></g>`;
  } else {
    const frameW = tablet ? art.w + 34 : 430, frameH = tablet ? art.h + 34 : 900;
    const factor = Math.min(maxW / frameW, maxH / frameH), dw = frameW * factor, dh = frameH * factor;
    const framed = tablet ? tabletFrame(art.content, art.w, art.h, index) : phoneFrame(art.content, index);
    s += `<g filter="url(#shadow)">${nested(framed, frameW, frameH, (w - dw) / 2, top + (maxH - dh) * .20, dw, dh)}</g>`;
  }
  return `<g transform="translate(${offset} 0)">${s}</g>`;
}
async function makeGallery(files, family, gap, label) {
  const tileW = family.tablet ? 340 : 260, tileH = Math.round(tileW * family.height / family.width), pad = 28;
  const width = pad * 2 + tileW * files.length + gap * (files.length - 1), height = tileH + 93;
  const input = files.map((file, index) => ({ file, left: pad + index * (tileW + gap) }));
  const comps = await Promise.all(input.map(async ({ file, left }) => ({ input: await sharp(path.join(output, file)).resize(tileW, tileH).png().toBuffer(), left, top: 65 })));
  const header = Buffer.from(`<svg width="${width}" height="52">${text(pad, 31, `${family.tablet ? 'iPad' : 'iPhone'} · 5 ordered panels · ${gap}px preview gutter · ${label}`, 20, '#33343B', 600)}</svg>`);
  await sharp({ create: { width, height, channels: 3, background: '#F4F4F6' } }).composite([{ input: header, left: 0, top: 0 }, ...comps]).png().toFile(path.join(output, `${family.tablet ? 'ipad' : 'iphone'}-gallery-gap-${gap}.png`));
}
async function makeViewportPreview(files, family, viewportWidth, cardWidth, gap, label) {
  const margin = viewportWidth < 500 ? 16 : 20;
  const cardHeight = cardWidth * family.height / family.width;
  const viewportHeight = Math.ceil(cardHeight + 113);
  let svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${viewportWidth}" height="${viewportHeight}">${rect(0, 0, viewportWidth, viewportHeight, 0, '#F4F4F6')}`;
  svg += text(margin, 25, `${family.tablet ? 'iPad' : 'iPhone'} · ${viewportWidth}px gallery viewport`, viewportWidth < 500 ? 14 : 18, '#33343B', 600);
  svg += text(margin, 48, label, viewportWidth < 500 ? 9 : 14, '#55555E');
  for (const [index, file] of files.entries()) {
    svg += photo(await dataURI(path.join(output, file)), margin + index * (cardWidth + gap), 70, cardWidth, cardHeight, 'none');
  }
  svg += '</svg>';
  await sharp(Buffer.from(svg), { limitInputPixels: 100000000 }).flatten({ background: '#F4F4F6' }).removeAlpha().png().toFile(path.join(output, `${family.tablet ? 'ipad' : 'iphone'}-gallery-viewport-${viewportWidth}.png`));
}
(async () => {
  await fs.mkdir(output, { recursive: true });
  const assets = await loadAssets(), icon = await dataURI(path.join(root, 'ProEstimate AI/Assets.xcassets/AppIcon.appiconset/Icon-iOS-Default-1024x1024@1x.png'));
  const geometryPath = path.join(output, 'gallery-geometry.json');
  const existingGeometry = JSON.parse(await fs.readFile(geometryPath, 'utf8').catch(() => '{}'));
  const referenceGapRatio = Number(requestedGapRatio ?? existingGeometry.referenceGapRatio ?? .06);
  if (!Number.isFinite(referenceGapRatio) || referenceGapRatio < 0 || referenceGapRatio > .25) throw new Error('Gallery gap ratio must be between 0 and .25');
  const geometry = { ...existingGeometry, referenceGapRatio, measurementSource: existingGeometry.measurementSource || 'Provisional gutter/card-width ratio; replace with observed App Store gallery geometry before final review.', familyOverrides: existingGeometry.familyOverrides || {} };
  await fs.writeFile(geometryPath, JSON.stringify(geometry, null, 2) + '\n');
  const manifest = {
    generatedAt: new Date().toISOString(), language: 'en-US', panelCount: panels.length,
    source: 'https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications', specificationCheckedAt: '2026-11-03',
    note: 'Five marketing panels. Historic captures and code-derived/previously generated illustrations are identified individually; no new device or simulator capture was made. Captions are English in every staged locale. RGB sRGB PNG without alpha.',
    palette, background: { strategy: 'Original orange-ribbon panorama sampled around virtual gallery gaps', referenceGapRatio, geometrySource: geometry.measurementSource, cropOffsetFormula: 'index * (panelWidth + virtualGapWidth)', previewGuttersPx: [8, 16, 28], note: 'The reference panorama is aligned for the configured gutter/card-width ratio. Other storefront widths may vary; alternate previews show the expected variation rather than claiming universal alignment.' },
    panels, families: [],
  };
  for (const family of families) {
    const dir = path.join(output, family.id); await fs.rm(dir, { recursive: true, force: true }); await fs.mkdir(dir, { recursive: true }); const files = [];
    const ratio = Number(geometry.familyOverrides[family.id]?.gapRatio ?? referenceGapRatio);
    if (!Number.isFinite(ratio) || ratio < 0 || ratio > .25) throw new Error(`Invalid gutter ratio for ${family.id}`);
    const virtualGapWidth = Math.round(family.width * ratio);
    const virtualWidth = family.width * panels.length + virtualGapWidth * (panels.length - 1);
    const foreground = await Promise.all(panels.map((panel, index) => makePanel(panel, index, family, icon, assets, index * (family.width + virtualGapWidth))));
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${virtualWidth}" height="${family.height}" viewBox="0 0 ${virtualWidth} ${family.height}">${backdrop(virtualWidth, family.height)}${foreground.join('')}</svg>`;
    const panorama = await sharp(Buffer.from(svg), { limitInputPixels: 100000000 }).flatten({ background: palette.ink }).removeAlpha().toColourspace('srgb').png().toBuffer();
    if (family.id === 'iphone-dynamic-island-large' || family.id === 'ipad-13') await fs.writeFile(path.join(output, `${family.tablet ? 'ipad' : 'iphone'}-editable-panorama.svg`), svg);
    for (const [index, panel] of panels.entries()) {
      const name = `${panel.slug}_${family.width}x${family.height}.png`, file = path.join(dir, name);
      await sharp(panorama).extract({ left: index * (family.width + virtualGapWidth), top: 0, width: family.width, height: family.height }).removeAlpha().png().toFile(file);
      const m = await sharp(file).metadata(); if (m.width !== family.width || m.height !== family.height || m.hasAlpha || m.channels !== 3) throw new Error(`Invalid App Store export ${file}`);
      files.push(`${family.id}/${name}`);
    }
    manifest.families.push({ ...family, gapRatio: ratio, virtualGapWidth, virtualPanoramaWidth: virtualWidth, cropOffsets: panels.map((_, i) => i * (family.width + virtualGapWidth)), files });
    if (family.id === 'iphone-dynamic-island-large' || family.id === 'ipad-13') {
      const previewWidth = family.tablet ? 340 : 260;
      const referenceGapPx = Math.round(virtualGapWidth / family.width * previewWidth);
      await makeGallery(files, family, referenceGapPx, 'REFERENCE virtual-gap panorama');
      for (const gap of manifest.background.previewGuttersPx) if (gap !== referenceGapPx) await makeGallery(files, family, gap, 'alternate storefront gutter; alignment varies');
      await makeViewportPreview(files, family, 1200, 273.328125, 20, family.tablet ? 'Reference calibration only · iPad geometry inferred from iPhone gallery' : 'Measured reference · cards 273.328125px · gutter 20px');
      await makeViewportPreview(files, family, 390, 260, 16, 'Compact alternative · 260px cards / 16px gutter · not a device capture');
    }
    console.log(`${family.id}: ${family.width} × ${family.height}, ${files.length} RGB PNGs`);
  }
  const sourceFiles = ['operations/validation-2026-10-30/comparison-source.jpg', 'operations/validation-2026-10-30/comparison-complete-photo.png', 'web/public/screenshots/projects.jpg', 'web/public/screenshots/materials.jpg', 'artifacts/app-store-listing/2026-10-30/assets/03-ipad-project.png', 'artifacts/app-store-listing/2026-10-30/assets/03-estimate-device.png', 'ProEstimate AI/Assets.xcassets/CategoryThumbs/02_luxury_bathroom.imageset/02_luxury_bathroom.jpg', 'ProEstimate AI/Assets.xcassets/CategoryThumbs/36_outdoor_patio.imageset/36_outdoor_patio.jpg'];
  const sources = { generatedAt: manifest.generatedAt, simulatorOpened: false, freshRuntimeCapture: false, screenshotPalette: 'ColorTokens.primaryOrange #FF9230; ColorTokens.brandDark #1C1C1E; ColorTokens.overlayBackground #0B0B0C', panels, sourceFiles: await Promise.all(sourceFiles.map(async (file) => ({ file, sha256: crypto.createHash('sha256').update(await fs.readFile(path.join(root, file))).digest('hex') }))), home: { representation: 'SVG illustration derived from the new Home hierarchy, not a runtime screenshot', values: 'Fictional sample account/projects; DashboardSummary.sample totals: $24,750 revenue, 7 active projects, 2 invoices due', implementationSource: 'Home hierarchy from 9bbcad4; estimate flow from bdb4531', verification: 'Compare final implemented Home against this illustration before representing it as a pixel-accurate capture' }, export: 'Deterministic SVG/Sharp layout composition. No provider API calls or Apple writes.' };
  await fs.writeFile(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  await fs.writeFile(path.join(output, 'sources.json'), JSON.stringify(sources, null, 2) + '\n');
  const reviewTemplate = await fs.readFile(path.join(root, 'scripts/app-store-gallery-preview.html'), 'utf8');
  await fs.writeFile(path.join(output, 'gallery-preview.html'), reviewTemplate.replace('__CAMPAIGN_MANIFEST__', JSON.stringify(manifest).replaceAll('<', '\\u003c')));
})().catch((error) => { console.error(error); process.exitCode = 1; });
