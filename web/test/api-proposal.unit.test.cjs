const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

function load(file, globals = {}) {
  const source = fs.readFileSync(path.join(__dirname, '../src', file), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(code, { exports: module.exports, require, process: { env: {} }, Headers, Date, URL, ...globals });
  return module.exports;
}

const now = Date.parse('2026-10-13T12:00:00Z');
class FixtureDate extends Date { static now() { return now; } }
const proposal = load('lib/proposal.ts', { Date: FixtureDate, require: () => ({}) });

test('proposal expiration preserves final decisions and honors explicit expired state', () => {
  for (const status of ['approved', 'declined']) {
    assert.equal(proposal.isProposalExpired({ status, expires_at: '2000-01-01T00:00:00Z' }), false);
  }
  assert.equal(proposal.isProposalExpired({ status: 'expired', expires_at: null }), true);
  assert.equal(proposal.isProposalExpired({ status: 'viewed', expires_at: new Date(now).toISOString() }), true);
  assert.equal(proposal.isProposalExpired({ status: 'sent', expires_at: new Date(now + 1000).toISOString() }), false);
  assert.equal(proposal.isProposalExpired({ status: 'sent', expires_at: 'invalid' }), false);
});

test('company website links allow web protocols only', () => {
  assert.equal(proposal.safeWebsiteURL('https://example.com'), 'https://example.com/');
  for (const value of [null, 'invalid', 'javascript:alert(1)', 'data:text/html,test', 'file:///tmp/test']) {
    assert.equal(proposal.safeWebsiteURL(value), null);
  }
});

test('API preserves Headers entries and normalizes a trailing base URL slash', async () => {
  let captured;
  const api = load('lib/api.ts', {
    process: { env: { NEXT_PUBLIC_API_BASE_URL: 'https://example.com/v1/' } },
    fetch: async (url, options) => { captured = { url, options }; return Response.json({ ok: true, data: 'success' }); },
  });
  assert.equal(await api.fetchAPI('/proposal', { headers: new Headers({ 'X-Test': 'retained' }) }), 'success');
  assert.equal(captured.url, 'https://example.com/v1/proposal');
  assert.equal(captured.options.headers.get('X-Test'), 'retained');
  assert.equal(captured.options.headers.get('Accept'), 'application/json');
});

test('malformed API envelopes produce APIError instead of TypeError', async () => {
  for (const value of [null, 'not an envelope', {}, { ok: 'true' }]) {
    const api = load('lib/api.ts', { fetch: async () => Response.json(value) });
    await assert.rejects(api.fetchAPI('/proposal'), error => error.name === 'APIError' && error.code === 'INVALID_RESPONSE');
  }
});

test('API errors preserve status and provider message for caller recovery', async () => {
  const api = load('lib/api.ts', { fetch: async () => Response.json({ ok: false, error: { code: 'NOT_FOUND', message: 'Proposal missing' } }, { status: 404 }) });
  await assert.rejects(api.fetchAPI('/proposal'), error => error.name === 'APIError' && error.status === 404 && error.message === 'Proposal missing');
});
