// Drive the headless preview through CDP. Plan is JSON, e.g.
// [{"wait":500},{"click":[1160,510]},{"shot":"chat"},{"type":"你好"},{"key":"Enter"},{"shot":"reply"}]
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';

const prefix = process.argv[2] ?? 'shots/flow';
const url = process.argv[3] ?? 'http://127.0.0.1:8137/';
const planPath = process.argv[4];
const waitInitial = Number(process.argv[5] ?? 9000);
const plan = planPath ? JSON.parse(await readFile(planPath, 'utf8')) : [];
const cdpBase = `http://127.0.0.1:${process.env.CDP_PORT ?? '9223'}`;

const target = await fetch(`${cdpBase}/json/new?${encodeURIComponent(url)}`, { method: 'PUT' }).then(r => r.json());
const ws = new WebSocket(target.webSocketDebuggerUrl);
let nextId = 0;
const pending = new Map();
const consoleEvents = [];
ws.addEventListener('message', event => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) {
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(`${message.error.message} (${message.error.code})`));
    else resolve(message.result);
  } else if (message.method === 'Runtime.exceptionThrown') {
    consoleEvents.push({ type: 'exception', text: message.params.exceptionDetails.text + ' ' + (message.params.exceptionDetails.exception?.description ?? '') });
  } else if (message.method === 'Runtime.consoleAPICalled') {
    const text = message.params.args.map(a => a.value ?? a.description ?? '').join(' ');
    if (text) consoleEvents.push({ type: 'console', level: message.params.type, text });
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
await send('Network.enable');
await send('Network.setBypassServiceWorker', { bypass: true });
await send('Emulation.setDeviceMetricsOverride', { width: 1600, height: 900, deviceScaleFactor: 1, mobile: false });
await send('Page.navigate', { url });
await new Promise(r => setTimeout(r, waitInitial));

let shotIndex = 0;
async function shot(name) {
  shotIndex += 1;
  const out = `${prefix}-${String(shotIndex).padStart(2, '0')}-${name}.png`;
  const data = await send('Page.captureScreenshot', { format: 'png', fromSurface: true });
  await mkdir(dirname(out), { recursive: true });
  await writeFile(out, Buffer.from(data.data, 'base64'));
  console.log('SHOT', out);
  return out;
}

async function click(x, y) {
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', buttons: 1, clickCount: 1 });
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', buttons: 0, clickCount: 1 });
}

async function press(key) {
  const code = key === 'Enter' ? 'Enter' : key;
  const vk = key === 'Enter' ? 13 : 0;
  await send('Input.dispatchKeyEvent', { type: 'keyDown', key: code, code, windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk });
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key: code, code, windowsVirtualKeyCode: vk, nativeVirtualKeyCode: vk });
}

for (const step of plan) {
  if (step.viewport) {
    await send('Emulation.setDeviceMetricsOverride', {
      width: Number(step.viewport[0]),
      height: Number(step.viewport[1]),
      deviceScaleFactor: 1,
      mobile: false,
    });
    await new Promise(r => setTimeout(r, Number(step.after ?? 900)));
  } else if (step.wait != null) {
    await new Promise(r => setTimeout(r, Number(step.wait)));
  } else if (step.click) {
    await click(Number(step.click[0]), Number(step.click[1]));
    await new Promise(r => setTimeout(r, Number(step.after ?? 700)));
  } else if (step.type != null) {
    await send('Input.insertText', { text: String(step.type) });
    await new Promise(r => setTimeout(r, Number(step.after ?? 350)));
  } else if (step.key) {
    await press(String(step.key));
    await new Promise(r => setTimeout(r, Number(step.after ?? 600)));
  } else if (step.move) {
    await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: Number(step.move[0]), y: Number(step.move[1]) });
    await new Promise(r => setTimeout(r, Number(step.after ?? 250)));
  } else if (step.scroll) {
    await send('Input.dispatchMouseEvent', {
      type: 'mouseWheel',
      x: Number(step.at?.[0] ?? 900),
      y: Number(step.at?.[1] ?? 400),
      deltaX: Number(step.scroll[0] ?? 0),
      deltaY: Number(step.scroll[1] ?? 0),
    });
    await new Promise(r => setTimeout(r, Number(step.after ?? 700)));
  } else if (step.eval) {
    const result = await send('Runtime.evaluate', { expression: String(step.eval), awaitPromise: true, returnByValue: true, userGesture: true });
    console.log('EVAL', JSON.stringify(result.result?.value ?? result.result?.description ?? result));
    await new Promise(r => setTimeout(r, Number(step.after ?? 500)));
  } else if (step.shot) {
    await shot(String(step.shot));
  }
}

const info = await send('Runtime.evaluate', {
  expression: `(() => {
    const fv = document.querySelector('flutter-view');
    const r = fv ? fv.getBoundingClientRect() : null;
    return { title: document.title, active: document.activeElement?.tagName, fv: r ? {x:r.x,y:r.y,width:r.width,height:r.height} : null, inner: {width: innerWidth, height: innerHeight} };
  })()`,
  returnByValue: true,
});
console.log('PAGE', JSON.stringify(info.result.value));
if (consoleEvents.length) console.log('EVENTS', JSON.stringify(consoleEvents, null, 2));
ws.close();
