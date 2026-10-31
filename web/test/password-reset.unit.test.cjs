const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

function compile(file) {
  return ts.transpileModule(fs.readFileSync(path.join(__dirname, '../src', file), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX },
  }).outputText;
}
const helperModule = { exports: {} };
vm.runInNewContext(compile('lib/password-reset.ts'), { exports: helperModule.exports, TextEncoder, URL, URLSearchParams });
const helpers = helperModule.exports;
const proof = 'a'.repeat(64);

test('reset token accepts fragment and legacy query proofs, rejecting missing/malformed/ambiguous proofs', () => {
  assert.equal(helpers.readPasswordResetToken(`https://example.com/reset-password#token=${proof}`), proof);
  assert.equal(helpers.readPasswordResetToken(`https://example.com/reset-password?token=${proof}`), proof);
  for (const suffix of ['', '#token=invalid', `#token=${proof}&token=${proof}`, `?token=${proof}#token=${proof}`]) {
    assert.equal(helpers.readPasswordResetToken(`https://example.com/reset-password${suffix}`), null);
  }
});

test('password validation matches server strength, confirmation and bcrypt UTF-8 boundaries', () => {
  assert.equal(helpers.validateNewPassword('Aa1' + 'x'.repeat(69), 'Aa1' + 'x'.repeat(69)), null);
  assert.equal(helpers.validateNewPassword('Aa1' + 'x'.repeat(70), 'Aa1' + 'x'.repeat(70)).field, 'password');
  assert.equal(helpers.validateNewPassword('Aa1' + '😀'.repeat(18), 'Aa1' + '😀'.repeat(18)).field, 'password');
  for (const password of ['Aa1tiny', 'nouppercase1', 'NOLOWERCASE1', 'NoNumberHere']) {
    assert.equal(helpers.validateNewPassword(password, password).field, 'password');
  }
  assert.equal(helpers.validateNewPassword('SecurePass1', 'different').field, 'confirmation');
});

class APIError extends Error { constructor(status) { super('Fixture error'); this.status = status; } }
function harness(respond, suffix = `#token=${proof}`) {
  const state = []; let cursor = 0; const effects = []; const requests = [];
  const history = [];
  const window = { location: { href: `https://example.com/reset-password${suffix}`, pathname: '/reset-password' }, history: { state: {}, replaceState(...args) { history.push(args); window.location.href = `https://example.com${args[2]}`; } }, addEventListener() {}, removeEventListener() {} };
  const react = {
    useState(initial) { const i = cursor++; if (!(i in state)) state[i] = typeof initial === 'function' ? initial() : initial; return [state[i], value => { state[i] = typeof value === 'function' ? value(state[i]) : value; }]; },
    useRef(initial) { const i = cursor++; if (!(i in state)) state[i] = { current: initial }; return state[i]; },
    useEffect(callback) { const i = cursor++; if (!(i in state)) { state[i] = true; effects.push(callback); } },
  };
  const module = { exports: {} };
  vm.runInNewContext(compile('app/reset-password/ResetPasswordForm.tsx'), {
    exports: module.exports, window, AbortSignal,
    require: name => name === 'react' ? react : name === '@/lib/password-reset' ? helpers : name === '@/lib/api' ? { APIError, fetchAPI: async (...args) => { requests.push(args); return respond(...args); } } : require(name),
  });
  const render = () => { cursor = 0; let tree = module.exports.ResetPasswordForm(); if (effects.length) { const effect = effects.shift(); effect(); effect(); cursor = 0; tree = module.exports.ResetPasswordForm(); } return tree; };
  return { render, requests, history };
}
function nodes(root) { if (!root || typeof root !== 'object') return []; if (Array.isArray(root)) return root.flatMap(nodes); return [root, ...nodes(root.props?.children)]; }
function text(root) { if (root == null || typeof root === 'boolean') return ''; if (Array.isArray(root)) return root.map(text).join(''); return typeof root === 'object' ? text(root.props?.children) : String(root); }
function node(tree, predicate) { const value = nodes(tree).find(predicate); assert.ok(value, 'Expected component element'); return value; }
function fill(h, id, value) { node(h.render(), n => n.type === 'input' && n.props.id === id).props.onChange({ target: { value } }); }
function submit(h) { return node(h.render(), n => n.type === 'form').props.onSubmit({ preventDefault() {} }); }

test('reset scrubs proof from URL, prevents duplicate submits and clears passwords on success', async () => {
  let resolve;
  const h = harness(() => new Promise(r => { resolve = r; }));
  assert.match(text(h.render()), /Choose a new password/);
  assert.equal(h.history.length, 1, 'Strict Mode effect replay must retain the original proof');
  assert.equal(h.history[0][2], '/reset-password');
  fill(h, 'reset-password', 'SecurePass1'); fill(h, 'reset-confirmation', 'SecurePass1');
  const pending = submit(h); await submit(h);
  assert.equal(h.requests.length, 1);
  assert.deepEqual(JSON.parse(h.requests[0][1].body), { token: proof, new_password: 'SecurePass1' });
  assert.equal(h.requests[0][1].referrerPolicy, 'no-referrer');
  assert.equal(h.requests[0][1].credentials, 'omit');
  assert.equal(node(h.render(), n => n.props?.id === 'reset-password').props.disabled, true);
  resolve({ message: 'Password updated' }); await pending;
  assert.match(text(h.render()), /Password updated/);
  assert.equal(nodes(h.render()).some(n => n.type === 'input'), false);
});

test('failed reset preserves input for retry; expired proof allows a fresh generic reset request', async () => {
  let calls = 0;
  const h = harness(async () => { if (++calls === 1) throw new Error('Network'); if (calls === 2) throw new APIError(400); return {}; });
  fill(h, 'reset-password', 'SecurePass1'); fill(h, 'reset-confirmation', 'SecurePass1');
  await submit(h);
  assert.match(text(node(h.render(), n => n.props?.role === 'alert')), /Check your connection/);
  assert.equal(node(h.render(), n => n.props?.id === 'reset-password').props.value, 'SecurePass1');
  await submit(h);
  assert.match(text(h.render()), /invalid or has expired/);
  node(h.render(), n => n.type === 'button' && text(n) === 'Request a new link').props.onClick();
  fill(h, 'reset-email', ' Person@Example.COM '); await submit(h);
  assert.deepEqual(JSON.parse(h.requests[2][1].body), { email: 'person@example.com' });
  assert.match(text(h.render()), /If an account uses that email/);
});

test('invalid/missing proof cannot post a password; mismatched confirmation stays local', async () => {
  const missing = harness(async () => {}, '#token=invalid');
  assert.match(text(missing.render()), /Email address/);
  assert.equal(nodes(missing.render()).some(n => n.props?.id === 'reset-password'), false);
  const h = harness(async () => {});
  fill(h, 'reset-password', 'SecurePass1'); fill(h, 'reset-confirmation', 'WrongPass1');
  await submit(h); assert.equal(h.requests.length, 0);
  assert.match(text(h.render()), /passwords do not match/);
});
