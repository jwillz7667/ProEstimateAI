// Browser regression tests with a local mock API; no production requests.
// Requires playwright and Chromium. Run with NODE_PATH if Playwright is
// supplied by the development environment rather than this package.
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { spawn } = require('node:child_process');
const { chromium } = require('playwright');
const path = require('node:path');

const apiPort = 14319;
const webPort = 14320;
let api, app, browser;
const fixture = {
  company: { name: 'Fixture Contractor', primary_color: '#FF9230' },
  project: { title: 'Fixture kitchen', project_type: 'KITCHEN' },
  estimate: { subtotal_materials: 100, subtotal_labor: 100, subtotal_other: 0,
    tax_amount: 0, discount_amount: 0, total_amount: 200, line_items: [] },
  proposal: { status: 'sent', title: 'Fixture proposal' },
  before_after_images: [],
};
before(async () => {
  api = http.createServer((req, res) => {
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ ok: true, data: fixture }));
  });
  await new Promise(resolve => api.listen(apiPort, '127.0.0.1', resolve));
  app = spawn(process.execPath, [require.resolve('next/dist/bin/next'), 'dev', '-H', '127.0.0.1', '-p', String(webPort)], {
    cwd: path.resolve(__dirname, '..'),
    env: { ...process.env, NEXT_PUBLIC_API_BASE_URL: `http://127.0.0.1:${apiPort}/v1`, API_BASE_URL: `http://127.0.0.1:${apiPort}/v1` },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let logs = '';
  app.stdout.on('data', chunk => { logs += chunk; });
  app.stderr.on('data', chunk => { logs += chunk; });
  const deadline = Date.now() + 90000;
  while (Date.now() < deadline) {
    if (app.exitCode !== null) throw new Error(logs);
    try {
      if ((await fetch(`http://127.0.0.1:${webPort}/proposal/fixture`)).ok) break;
    } catch {}
    await new Promise(resolve => setTimeout(resolve, 300));
  }
  assert.ok(Date.now() < deadline, logs);
  browser = await chromium.launch({ headless: true,
    ...(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {}),
    args: ['--no-sandbox'],
  });
}, { timeout: 120000 });
after(async () => {
  await browser?.close();
  app?.kill('SIGTERM');
  await new Promise(resolve => api ? api.close(resolve) : resolve());
});
for (const decision of ['approved', 'declined']) {
  test(`${decision}: failed response preserves form and message, retry is single-submit, cancel returns to review`, async () => {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    let posts = [];
    let release;
    await page.route(`http://127.0.0.1:${apiPort}/v1/proposals/share/fixture/respond`, async route => {
      if (route.request().method() === 'OPTIONS') {
        await route.fulfill({ status: 204, headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'content-type' } });
        return;
      }
      posts.push(route.request().postDataJSON());
      if (posts.length === 1) {
        await route.fulfill({ status: 503, headers: { 'Access-Control-Allow-Origin': '*' }, contentType: 'application/json', body: JSON.stringify({ ok: false, error: { message: 'Temporary fixture outage', code: 'UNAVAILABLE' } }) });
      } else {
        await new Promise(resolve => { release = resolve; });
        await route.fulfill({ status: 200, headers: { 'Access-Control-Allow-Origin': '*' }, contentType: 'application/json', body: JSON.stringify({ ok: true, data: fixture }) });
      }
    });
    await page.goto(`http://127.0.0.1:${webPort}/proposal/fixture`);
    const opener = page.getByRole('button', { name: decision === 'approved' ? 'Approve Proposal' : 'Decline', exact: true });
    const confirmName = decision === 'approved' ? 'Confirm Approval' : 'Confirm Decline';
    await opener.click();
    await page.getByRole('textbox', { name: 'Message to your contractor' }).fill('Fixture message');
    await page.getByRole('button', { name: confirmName }).click();
    await page.getByRole('alert').waitFor();
    assert.equal(await page.getByRole('alert').textContent(), 'Temporary fixture outage');
    assert.equal(await page.getByRole('textbox').inputValue(), 'Fixture message');
    await page.getByRole('button', { name: 'Keep Reviewing' }).click();
    await opener.waitFor();
    await opener.click();
    assert.equal(await page.getByRole('textbox').inputValue(), '');
    await page.getByRole('textbox').fill('Retry fixture');
    // Dispatch both in one task to cover the pre-render double-click race.
    await page.getByRole('button', { name: confirmName }).evaluate(button => { button.click(); button.click(); });
    await page.getByRole('button', { name: 'Sending response…' }).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Keep Reviewing' }).isDisabled(), true);
    assert.equal(await page.getByRole('textbox').isDisabled(), true);
    await page.waitForTimeout(100);
    assert.equal(posts.length, 2);
    assert.deepEqual(posts[1], { decision, message: 'Retry fixture' });
    release();
    await page.getByRole('status').filter({ hasText: 'Your response has been recorded.' }).waitFor();
    await page.screenshot({ path: process.env.SCREENSHOT_DIR ? `${process.env.SCREENSHOT_DIR}/proposal-${decision}.png` : `/tmp/proposal-${decision}.png`, fullPage: true });
    await page.close();
  }, { timeout: 45000 });
}
