const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
const React = require('react');
const { renderToStaticMarkup } = require('react-dom/server');
function load(file, requireFn = require) {
  const code = ts.transpileModule(fs.readFileSync(path.join(__dirname, '../src', file), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX } }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(code, { exports: module.exports, require: requireFn, Intl, Date, URL });
  return module.exports;
}
const helpers = load('lib/proposal.ts', () => ({}));
const { ChangeOrderReview } = load('app/proposal/[token]/ChangeOrderReview.tsx', name => name === '@/lib/proposal' ? helpers : require(name));
const comparison = { id: 'co', title: 'Extra work', reason: 'Requested <script>alert(1)</script>', currency_code: 'USD', base_estimate_number: 'EST-1', base_version: 1, base_document_hash: 'a'.repeat(64), base_total: 100, new_total: 150, change_amount: 50, subtotal_delta: 50, tax_delta: 0, discount_delta: 0, base_scope: { line_items: [{ name: 'Original scope', description: null, quantity: 1, unit: 'job', line_total: 100 }], assumptions: 'Sound framing', exclusions: 'Permits' }, billing_effect: 'additional_invoice' };
test('customer comparison shows old and revised scope/total and identifies the additional amount without rebilling the contract', () => {
  const html = renderToStaticMarkup(React.createElement(ChangeOrderReview, { comparison }));
  for (const text of ['Previously approved total', 'Revised contract total', 'Contract increase', '+$50.00', 'Original scope', 'Sound framing', 'Permits', 'not a second bill for the full project']) assert.ok(html.includes(text), text);
  assert.ok(!html.includes('<script>'));
  assert.ok(html.includes('&lt;script&gt;'));
});
test('credit and zero-price changes describe credit honestly and never promise a cash refund', () => {
  const credit = renderToStaticMarkup(React.createElement(ChangeOrderReview, { comparison: { ...comparison, new_total: 80, change_amount: -20, subtotal_delta: -20, billing_effect: 'credit_note' } }));
  assert.ok(credit.includes('Contract reduction'));
  assert.ok(credit.includes('−$20.00'));
  assert.ok(credit.includes('not a cash refund'));
  assert.ok(helpers.changeOrderBillingExplanation({ ...comparison, billing_effect: 'no_price_change' }).includes('without changing the contract price'));
  assert.ok(helpers.changeOrderBillingExplanation({ ...comparison, billing_effect: 'included_in_first_invoice' }).includes('not a separate payment request'));
});
