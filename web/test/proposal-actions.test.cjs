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
let isProposalUnavailable = false;
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
    const token = req.url.split('/').pop();
    if (token === 'recover' && isProposalUnavailable) {
      res.statusCode = 503;
      res.end(JSON.stringify({ ok: false, error: { code: 'UNAVAILABLE', message: 'Temporary fixture outage' } }));
      return;
    }
    const data = ['approved', 'declined', 'expired'].includes(token)
      ? { ...fixture, proposal: { ...fixture.proposal, status: token, expires_at: token === 'expired' ? null : '2000-01-01T00:00:00Z' } }
      : token === 'unsafe-website' ? { ...fixture, company: { ...fixture.company, website_url: 'javascript:alert(1)' } }
      : fixture;
    res.end(JSON.stringify({ ok: true, data }));
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
    const responseError = page.getByRole('alert').filter({ hasText: 'Temporary fixture outage' });
    await responseError.waitFor();
    assert.equal(await responseError.textContent(), 'Temporary fixture outage');
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

test('final decisions remain visible after expiry; explicit expired proposals explain closure', async () => {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  for (const status of ['approved', 'declined', 'expired']) {
    await page.goto(`http://127.0.0.1:${webPort}/proposal/${status}`);
    assert.equal(await page.locator('header').getByText(status[0].toUpperCase() + status.slice(1), { exact: true }).count(), 1);
    assert.equal(await page.getByRole('button', { name: 'Approve Proposal', exact: true }).count(), 0);
    if (status === 'expired') assert.equal(await page.getByText('This proposal has expired', { exact: true }).count(), 1);
  }
  await page.screenshot({ path: process.env.SCREENSHOT_DIR ? `${process.env.SCREENSHOT_DIR}/proposal-expired.png` : '/tmp/proposal-expired.png', fullPage: true });
  await page.close();
});

test('proposal print opens the native print flow and hides response controls on paper', async () => {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await page.goto(`http://127.0.0.1:${webPort}/proposal/fixture`);
  await page.evaluate(() => { window.printCalls = 0; window.print = () => { window.printCalls++; }; });
  await page.getByRole('button', { name: 'Print or save PDF', exact: true }).click();
  assert.equal(await page.evaluate(() => window.printCalls), 1);
  await page.emulateMedia({ media: 'print' });
  assert.equal(await page.getByRole('button', { name: 'Print or save PDF', exact: true }).isVisible(), false);
  assert.equal(await page.getByRole('button', { name: 'Approve Proposal', exact: true }).isVisible(), false);
  assert.equal(await page.getByRole('heading', { name: 'Pricing', exact: true }).isVisible(), true);
  await page.screenshot({ path: process.env.SCREENSHOT_DIR ? `${process.env.SCREENSHOT_DIR}/proposal-print.png` : '/tmp/proposal-print.png', fullPage: true });
  await page.close();
});

test('shared page prevents unsafe website navigation and suppresses referrers', async () => {
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${webPort}/proposal/unsafe-website`);
  assert.equal(await page.locator('a[href^="javascript:"]').count(), 0);
  assert.equal(await page.locator('meta[name="referrer"]').getAttribute('content'), 'no-referrer');
  await page.close();
});

test('proposal connection failure offers retry and recovers after the API returns', async () => {
  const page = await browser.newPage();
  isProposalUnavailable = true;
  try {
    await page.goto(`http://127.0.0.1:${webPort}/proposal/recover`);
    await page.getByRole('heading', { name: 'Unable to load this proposal', exact: true }).waitFor();
    isProposalUnavailable = false;
    await page.getByRole('button', { name: 'Try again', exact: true }).click();
    await page.getByRole('heading', { name: 'Fixture proposal', exact: true }).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Approve Proposal', exact: true }).count(), 1);
  } finally {
    isProposalUnavailable = false;
    await page.close();
  }
});

test('current plan marketing and upgraded carousel render without browser errors', async () => {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(`http://127.0.0.1:${webPort}/`);
  await page.addStyleTag({ content: 'html { scroll-behavior: auto !important; }' });
  await page.locator('#pricing').scrollIntoViewIfNeeded();
  const proCard = await page.getByRole('heading', { name: 'Pro', exact: true }).locator('..').elementHandle();
  await page.waitForFunction(card => getComputedStyle(card).opacity === '1', proCard);
  assert.equal(await page.getByRole('heading', { name: 'Premium', exact: true }).count(), 0);
  assert.equal(await page.getByText('2 AI project creations / month', { exact: true }).count(), 1);
  assert.ok(await page.locator('.swiper-slide').count() > 0);
  assert.deepEqual(errors, []);
  await page.locator('#pricing').screenshot({ path: process.env.SCREENSHOT_DIR ? `${process.env.SCREENSHOT_DIR}/pricing.png` : '/tmp/pricing.png' });
  await page.close();
});
