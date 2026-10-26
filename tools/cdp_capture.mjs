// Capture the local Flutter web app through headless Edge + Chrome DevTools Protocol.
// Usage: node tools/cdp_capture.mjs <out.png> [url] [waitMs] [evaluateScript]
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';

const out = process.argv[2] ?? 'shots/app.png';
const url = process.argv[3] ?? 'http://127.0.0.1:8137/';
const waitMs = Number(process.argv[4] ?? 9000);
const evaluateScript = process.argv[5] ?? '';
const cdpBase = `http://127.0.0.1:${process.env.CDP_PORT ?? '9223'}`;

const target = await fetch(`${cdpBase}/json/new?${encodeURIComponent(url)}`, { method: 'PUT' }).then(r => r.json());
const ws = new WebSocket(target.webSocketDebuggerUrl);
let nextId = 0;
const pending = new Map();
const events = [];

ws.addEventListener('message', event => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) {
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(`${message.error.message}: ${message.error.code}`));
    else resolve(message.result);
  } else if (message.method) {
    if (message.method === 'Runtime.consoleAPICalled') {
      events.push({ type: 'console', level: message.params.type, text: message.params.args.map(a => a.value ?? a.description ?? '').join(' ') });
    }
    if (message.method === 'Log.entryAdded') {
      events.push({ type: 'log', level: message.params.entry.level, text: message.params.entry.text });
    }
    if (message.method === 'Runtime.exceptionThrown') {
      events.push({ type: 'exception', text: message.params.exceptionDetails.text + ' ' + (message.params.exceptionDetails.exception?.description ?? '') });
    }
  }
});

const send = (method, params = {}) => new Promise((resolve, reject) => {
  const id = ++nextId;
  pending.set(id, { resolve, reject });
  ws.send(JSON.stringify({ id, method, params }));
});

await new Promise((resolve, reject) => {
  ws.addEventListener('open', resolve, { once: true });
  ws.addEventListener('error', reject, { once: true });
});

await send('Page.enable');
await send('Runtime.enable');
await send('Log.enable');
await send('Network.enable');
await send('Network.setBypassServiceWorker', { bypass: true });
await send('Emulation.setDeviceMetricsOverride', {
  width: 1600,
  height: 900,
  deviceScaleFactor: 1,
  mobile: false,
});
await send('Page.navigate', { url });
await new Promise(resolve => setTimeout(resolve, waitMs));

if (evaluateScript) {
  try {
    const result = await send('Runtime.evaluate', {
      expression: evaluateScript,
      awaitPromise: true,
      returnByValue: true,
      userGesture: true,
    });
    console.log('EVAL:', JSON.stringify(result.result?.value ?? result.result?.description ?? result, null, 2));
    await new Promise(resolve => setTimeout(resolve, 1200));
  } catch (error) {
    console.log('EVAL_ERROR:', error.message);
  }
}

const info = await send('Runtime.evaluate', {
  expression: `(() => {
    const fv = document.querySelector('flutter-view');
    const r = fv ? fv.getBoundingClientRect() : null;
    return {
      title: document.title,
      bodyText: document.body.innerText.slice(0, 500),
      flutterView: r ? { x: r.x, y: r.y, width: r.width, height: r.height } : null,
      inner: { width: innerWidth, height: innerHeight, dpr: devicePixelRatio },
      scroll: { width: document.documentElement.scrollWidth, height: document.documentElement.scrollHeight },
    };
  })()`,
  returnByValue: true,
});
console.log('PAGE:', JSON.stringify(info.result.value, null, 2));
console.log('EVENTS:', JSON.stringify(events.slice(-20), null, 2));

const shot = await send('Page.captureScreenshot', { format: 'png', fromSurface: true });
await mkdir(dirname(out), { recursive: true });
await writeFile(out, Buffer.from(shot.data, 'base64'));
console.log('SHOT:', out);

ws.close();
await fetch(`${cdpBase}/json/close/${target.id}`);
