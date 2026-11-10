const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

function loadRoute(fetch) {
  const source = fs.readFileSync(path.join(__dirname, '../src/app/api/support/chat/route.ts'), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(code, {
    exports: module.exports, require, process: { env: { DEEPSEEK_API_KEY: 'synthetic-test-key' } },
    fetch, Response, ReadableStream, TextEncoder, TextDecoder, AbortSignal,
  });
  return module.exports.POST;
}
const request = body => new Request('http://localhost/api/support/chat', { method: 'POST', body: JSON.stringify(body) });

test('support route rejects null and non-object JSON without calling the provider', async () => {
  let calls = 0;
  const post = loadRoute(async () => { calls++; });
  for (const body of [null, 1, 'question', [], { messages: null }]) {
    assert.equal((await post(request(body))).status, 400);
  }
  assert.equal(calls, 0);
});

test('support route recovers from network failure and hides raw provider details', async () => {
  for (const fetch of [async () => { throw new Error('Network down'); }, async () => new Response('private provider detail', { status: 500 })]) {
    const response = await loadRoute(fetch)(request({ messages: [{ role: 'user', content: 'Help' }] }));
    assert.equal(response.status, 502);
    assert.match(await response.text(), /temporarily unavailable/);
  }
});

test('support stream preserves split Unicode and a final frame without newline', async () => {
  const bytes = new TextEncoder().encode('data: {"choices":[{"delta":{"content":"Café"}}]}\n\ndata: {"choices":[{"delta":{"content":" — help"}}]}');
  const eAccent = bytes.indexOf(0xc3);
  const upstream = new ReadableStream({ start(controller) { controller.enqueue(bytes.slice(0, eAccent + 1)); controller.enqueue(bytes.slice(eAccent + 1)); controller.close(); } });
  const response = await loadRoute(async () => new Response(upstream))(request({ messages: [{ role: 'user', content: 'Help' }] }));
  assert.equal(response.status, 200);
  assert.equal(await response.text(), 'Café — help');
});

test('support prompt matches current plans and trims forwarded history', async () => {
  let payload;
  const post = loadRoute(async (_, init) => { payload = JSON.parse(init.body); return new Response('data: [DONE]\n\n'); });
  await post(request({ messages: Array.from({ length: 12 }, (_, index) => ({ role: 'user', content: String(index) })) }));
  assert.equal(payload.messages.length, 11);
  assert.equal(payload.messages[1].content, '2');
  assert.match(payload.messages[0].content, /suggestions require an active Apple trial or paid Pro subscription/);
  assert.match(payload.messages[0].content, /20 AI preview generations/);
  assert.match(payload.messages[0].content, /Premium subscriptions are no longer offered/);
});

function harness(fetch) {
  const state = [];
  let cursor = 0;
  const react = {
    useState(initial) { const index = cursor++; if (!(index in state)) state[index] = initial; return [state[index], value => { state[index] = typeof value === 'function' ? value(state[index]) : value; }]; },
    useRef(initial) { const index = cursor++; if (!(index in state)) state[index] = { current: initial }; return state[index]; },
    useCallback(fn) { return fn; }, useEffect() {},
  };
  const source = fs.readFileSync(path.join(__dirname, '../src/app/support/SupportChat.tsx'), 'utf8');
  const code = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX } }).outputText;
  const module = { exports: {} };
  let id = 0;
  vm.runInNewContext(code, { exports: module.exports, require: name => name === 'react' ? react : require(name), crypto: { randomUUID: () => `fixture-${id++}` }, fetch, TextDecoder, Error });
  return { render() { cursor = 0; return module.exports.SupportChat(); } };
}
function nodes(root) { if (!root || typeof root !== 'object') return []; if (Array.isArray(root)) return root.flatMap(nodes); return [root, ...nodes(root.props?.children)]; }
function find(root, predicate) { const match = nodes(root).find(predicate); assert.ok(match); return match; }

test('support double submit sends once; failed question is restored for a safe retry', async () => {
  let calls = 0, release;
  const h = harness(async () => { calls++; await new Promise(resolve => { release = resolve; }); return new Response('Unavailable', { status: 503 }); });
  find(h.render(), n => n.type === 'textarea').props.onChange({ target: { value: ' Keep my question ' } });
  const form = find(h.render(), n => n.type === 'form');
  form.props.onSubmit({ preventDefault() {} }); form.props.onSubmit({ preventDefault() {} });
  assert.equal(calls, 1);
  assert.equal(find(h.render(), n => n.type === 'textarea').props.disabled, true);
  release();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(find(h.render(), n => n.type === 'textarea').props.value, 'Keep my question');
  assert.equal(find(h.render(), n => n.props?.role === 'alert').props.children[0], 'Unavailable');
  const bubbles = nodes(h.render()).filter(n => typeof n.type === 'function' && n.type.name === 'MessageBubble');
  assert.equal(bubbles.length, 1, 'Failed turn must not remain in future conversation history');
});

test('support Enter does not submit during input composition and question has a label', () => {
  let calls = 0;
  const h = harness(async () => { calls++; return new Response('ok'); });
  find(h.render(), n => n.type === 'textarea').props.onChange({ target: { value: 'Question' } });
  const field = find(h.render(), n => n.type === 'textarea');
  field.props.onKeyDown({ key: 'Enter', shiftKey: false, nativeEvent: { isComposing: true }, preventDefault() { throw new Error('Composition must continue'); } });
  assert.equal(calls, 0);
  assert.equal(field.props.maxLength, 2000);
  assert.equal(field.props['aria-label'], 'Your question about ProEstimate AI');
});
