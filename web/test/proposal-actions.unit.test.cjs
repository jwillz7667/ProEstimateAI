// Dependency-free component-state tests. Browser coverage lives alongside this
// file; this harness tests the real component with deterministic React hooks.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
const source = fs.readFileSync(path.join(__dirname, '../src/app/proposal/[token]/ProposalActions.tsx'), 'utf8');
const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX } }).outputText;
function harness(respond) {
  const state = [];
  let cursor = 0, pending = false, task, refreshed = 0;
  const react = {
    useState(initial) { const index = cursor++; if (!(index in state)) state[index] = initial; return [state[index], value => { state[index] = typeof value === 'function' ? value(state[index]) : value; }]; },
    useRef(initial) { const index = cursor++; if (!(index in state)) state[index] = { current: initial }; return state[index]; },
    useId() { return 'message-fixture'; },
    useTransition() { return [pending, fn => { pending = true; task = fn().finally(() => { pending = false; }); }]; },
  };
  const module = { exports: {} };
  vm.runInNewContext(code, { exports: module.exports, require: name => {
    if (name === 'react') return react;
    if (name === 'next/navigation') return { useRouter: () => ({ refresh() { refreshed++; } }) };
    if (name === '@/lib/proposal') return { respondToSharedProposal: respond };
    return require(name);
  }, Error });
  const render = () => { cursor = 0; return module.exports.ProposalActions({ token: 'fixture' }); };
  return { render, settle: () => task, refreshed: () => refreshed };
}
function nodes(root) {
  if (!root || typeof root !== 'object') return [];
  if (Array.isArray(root)) return root.flatMap(nodes);
  return [root, ...nodes(root.props?.children)];
}
function text(node) { if (node === null || node === undefined || typeof node === 'boolean') return ''; if (typeof node !== 'object') return String(node); if (Array.isArray(node)) return node.map(text).join(''); return text(node.props?.children); }
function find(root, predicate) { const match = nodes(root).find(predicate); assert.ok(match, 'Expected component node'); return match; }
function button(root, label) { return find(root, node => node.type === 'button' && text(node) === label); }
for (const decision of ['approved', 'declined']) {
  test(`${decision}: rejection preserves decision/message, allows cancel and safe retry`, async () => {
    const calls = [];
    let resolve;
    const h = harness(async (...args) => { calls.push(args); if (calls.length === 1) throw new Error('Temporary outage'); await new Promise(r => { resolve = r; }); });
    const open = decision === 'approved' ? 'Approve Proposal' : 'Decline';
    const confirm = decision === 'approved' ? 'Confirm Approval' : 'Confirm Decline';
    button(h.render(), open).props.onClick();
    find(h.render(), n => n.type === 'textarea').props.onChange({ target: { value: 'Keep this message' } });
    button(h.render(), confirm).props.onClick();
    await h.settle();
    assert.equal(text(find(h.render(), n => n.props?.role === 'alert')), 'Temporary outage');
    assert.equal(find(h.render(), n => n.type === 'textarea').props.value, 'Keep this message');
    button(h.render(), 'Keep Reviewing').props.onClick();
    button(h.render(), open).props.onClick();
    assert.equal(find(h.render(), n => n.type === 'textarea').props.value, '');
    find(h.render(), n => n.type === 'textarea').props.onChange({ target: { value: ' Retry message ' } });
    const retry = button(h.render(), confirm);
    retry.props.onClick(); retry.props.onClick();
    assert.equal(calls.length, 2, 'Synchronous double clicks must produce only one request');
    assert.equal(button(h.render(), 'Keep Reviewing').props.disabled, true);
    button(h.render(), 'Keep Reviewing').props.onClick();
    assert.equal(find(h.render(), n => n.type === 'textarea').props.disabled, true);
    assert.deepEqual(calls[1], ['fixture', decision, 'Retry message']);
    resolve(); await h.settle();
    assert.equal(h.refreshed(), 1);
    assert.equal(text(find(h.render(), n => n.props?.role === 'status')), 'Your response has been recorded. Thank you.');
  });
}
test('contractor message has a programmatically associated accessible label', () => {
  const h = harness(async () => {});
  button(h.render(), 'Approve Proposal').props.onClick();
  const form = h.render();
  assert.equal(find(form, n => n.type === 'label').props.htmlFor, find(form, n => n.type === 'textarea').props.id);
});
test('free-preview CTA matches pricing and backend starter allowance', () => {
  const root = path.resolve(__dirname, '../..');
  const limits = fs.readFileSync(path.join(root, 'backend/src/lib/limits.ts'), 'utf8');
  const pricing = fs.readFileSync(path.join(root, 'web/src/components/Pricing.tsx'), 'utf8');
  const cta = fs.readFileSync(path.join(root, 'web/src/components/CTA.tsx'), 'utf8');
  assert.match(limits, /FREE_TIER_AI_GENERATION_CREDITS\s*=\s*5/);
  assert.match(pricing, /5 AI preview generations \(lifetime\)/);
  assert.match(cta, /Five full AI previews/);
});
