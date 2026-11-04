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
function harness(respond, props = {}) {
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
  const render = () => { cursor = 0; return module.exports.ProposalActions({ token: 'fixture', documentHash: 'a'.repeat(64), consentText: 'Fixture acknowledgement', consentVersion: 'quote-acceptance-v1', ...props }); };
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
function fillSignature(h) {
  find(h.render(), n => n.type === 'input' && n.props.name === 'signer_name').props.onChange({ target: { value: 'Jordan Customer' } });
  find(h.render(), n => n.type === 'input' && n.props.type === 'checkbox').props.onChange({ target: { checked: true } });
}
function confirm(h) { find(h.render(), n => n.type === 'form').props.onSubmit({ preventDefault() {} }); }
for (const decision of ['approved', 'declined']) {
  test(`${decision}: rejection preserves inputs, allows cancel and single-submit retry`, async () => {
    const calls = [];
    let resolve;
    const h = harness(async (...args) => { calls.push(args); if (calls.length === 1) throw new Error('Temporary outage'); await new Promise(r => { resolve = r; }); });
    const open = decision === 'approved' ? 'Approve Proposal' : 'Decline';
    button(h.render(), open).props.onClick();
    if (decision === 'approved') fillSignature(h);
    find(h.render(), n => n.type === 'textarea').props.onChange({ target: { value: 'Keep this message' } });
    confirm(h); await h.settle();
    assert.equal(text(find(h.render(), n => n.props?.role === 'alert')), 'Temporary outage');
    assert.equal(find(h.render(), n => n.type === 'textarea').props.value, 'Keep this message');
    if (decision === 'approved') assert.equal(find(h.render(), n => n.type === 'input' && n.props.name === 'signer_name').props.value, 'Jordan Customer');
    button(h.render(), 'Keep Reviewing').props.onClick();
    button(h.render(), open).props.onClick();
    assert.equal(find(h.render(), n => n.type === 'textarea').props.value, '');
    if (decision === 'approved') fillSignature(h);
    find(h.render(), n => n.type === 'textarea').props.onChange({ target: { value: ' Retry message ' } });
    const submit = find(h.render(), n => n.type === 'form').props.onSubmit;
    submit({ preventDefault() {} }); submit({ preventDefault() {} });
    assert.equal(calls.length, 2, 'Synchronous repeated submits produce one request');
    assert.equal(button(h.render(), 'Keep Reviewing').props.disabled, true);
    button(h.render(), 'Keep Reviewing').props.onClick();
    assert.equal(find(h.render(), n => n.type === 'textarea').props.disabled, true);
    assert.equal(calls[1][0], 'fixture'); assert.equal(calls[1][1], decision); assert.equal(calls[1][2], 'Retry message');
    assert.equal(calls[1][4], 'a'.repeat(64));
    if (decision === 'approved') { assert.equal(calls[1][3].signer_name, 'Jordan Customer'); assert.equal(calls[1][3].acceptance_consent, true); }
    else assert.equal(calls[1][3], undefined);
    resolve(); await h.settle();
    assert.equal(h.refreshed(), 1);
    assert.equal(text(find(h.render(), n => n.props?.role === 'status')), 'Your response has been recorded. Thank you.');
  });
}
test('approval requires name, explicit consent and a verified document reference', async () => {
  let calls = 0;
  const h = harness(async () => { calls++; });
  button(h.render(), 'Approve Proposal').props.onClick();
  assert.equal(button(h.render(), 'Confirm Approval').props.disabled, true);
  confirm(h); assert.equal(calls, 0);
  fillSignature(h);
  assert.equal(button(h.render(), 'Confirm Approval').props.disabled, false);
  confirm(h); await h.settle(); assert.equal(calls, 1);
  const unavailable = harness(async () => { calls++; }, { documentHash: null });
  button(unavailable.render(), 'Approve Proposal').props.onClick(); fillSignature(unavailable);
  assert.equal(button(unavailable.render(), 'Confirm Approval').props.disabled, true);
  confirm(unavailable); assert.equal(calls, 1);
});
test('a change request requires details and sends its exact reviewed version', async () => {
  const calls = [];
  const h = harness(async (...args) => calls.push(args));
  button(h.render(), 'Request Changes').props.onClick();
  assert.equal(button(h.render(), 'Send Change Request').props.disabled, true);
  find(h.render(), n => n.type === 'textarea').props.onChange({ target: { value: ' Use oak ' } });
  confirm(h); await h.settle();
  assert.equal(calls[0][1], 'changes_requested'); assert.equal(calls[0][2], 'Use oak'); assert.equal(calls[0][4], 'a'.repeat(64));
});
test('every form input has an associated accessible label and orange buttons have dark text', () => {
  const h = harness(async () => {});
  assert.equal(button(h.render(), 'Approve Proposal').props.style.color, '#000000');
  button(h.render(), 'Approve Proposal').props.onClick();
  for (const input of nodes(h.render()).filter(n => n.type === 'input' || n.type === 'textarea')) {
    assert.ok(nodes(h.render()).some(n => n.type === 'label' && n.props.htmlFor === input.props.id));
  }
});
test('public pricing requires a trial or subscription for AI while manual tools stay free', () => {
  const root = path.resolve(__dirname, '../..');
  const limits = fs.readFileSync(path.join(root, 'backend/src/lib/limits.ts'), 'utf8');
  const pricing = fs.readFileSync(path.join(root, 'web/src/components/Pricing.tsx'), 'utf8');
  const cta = fs.readFileSync(path.join(root, 'web/src/components/CTA.tsx'), 'utf8');
  assert.match(limits, /FREE_TIER_AI_GENERATION_CREDITS\s*=\s*0/);
  assert.match(pricing, /Keep manual project tools free/);
  assert.match(cta, /AI features require Pro/);
});
