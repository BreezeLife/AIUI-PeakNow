// Browser Ink validation only. Device/Studio checks are separate.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';

if (!process.env.PLAYWRIGHT_MODULE) throw Error('Set PLAYWRIGHT_MODULE to the installed playwright index.mjs.');
const { chromium } = await import(pathToFileURL(process.env.PLAYWRIGHT_MODULE));
const browser = await chromium.launch({ headless: true, ...(process.env.CHROME_BIN ? { executablePath: process.env.CHROME_BIN } : {}) });
const page = await browser.newPage({ viewport: { width: 1000, height: 750 }, deviceScaleFactor: 2 });
const errors = [], templateWarnings = [], serviceErrors = [];
page.on('pageerror', e => errors.push(e.message));
page.on('console', m => {
  if (m.type() === 'error' && m.text().includes('status of 503')) serviceErrors.push(m.text());
  else if (m.type() === 'error' && !m.text().includes('404')) errors.push(m.text());
  if (m.text().includes('Template variable')) templateWarnings.push(m.text());
});
await page.route('**/peaknow-preview.html', async route => {
  const response = await route.fetch();
  const body = (await response.text()).replace('https://esm.sh/@yodaos-pkg/ink"', 'https://esm.sh/@yodaos-pkg/ink@0.17.0"')
    .replace('currentView = view;', 'currentView = view; window.testView = view; window.testFiles = bundleFiles(state.files); view.setTarget("_blank");');
  await route.fulfill({ response, body });
});
const screenshots = path.resolve('docs/screenshots'); fs.mkdirSync(screenshots, { recursive: true });
async function shot(name, region) {
  const bytes = await page.locator('canvas').screenshot({ path: path.join(screenshots, name + '.png') });
  if (region) {
    const count = await page.evaluate(async ({ data, region }) => {
      const picture = new Image(); picture.src = 'data:image/png;base64,' + data; await picture.decode();
      const canvas = document.createElement('canvas'); canvas.width = picture.width; canvas.height = picture.height;
      const context = canvas.getContext('2d'); context.drawImage(picture, 0, 0);
      const scale = picture.width / 480, [x, y, w, h] = region;
      const pixels = context.getImageData(x * scale, y * scale, w * scale, h * scale).data;
      let count = 0; for (let i = 0; i < pixels.length; i += 4) if (pixels[i + 1] > 150 && pixels[i + 1] > pixels[i] * 1.3) count++;
      return count;
    }, { data: bytes.toString('base64'), region });
    assert.ok(count > 500, `${name}: expected visible content in ${region}, found ${count} green pixels`);
  }
}
async function key(code, count = 1) {
  for (let i = 0; i < count; i++) {
    await page.evaluate(code => { window.testView.dispatchInput('keydown', code); window.testView.dispatchInput('keyup', code); }, code);
    await page.waitForTimeout(350);
  }
}
async function ready() {
  await page.waitForFunction(() => window.testView && /ready/i.test(document.querySelector('#preview-status').textContent));
  await page.waitForTimeout(350);
}
try {
  await page.goto(process.env.PREVIEW_URL || 'http://127.0.0.1:8775/peaknow-preview.html'); await ready();
  await shot('splash-en'); await page.waitForTimeout(5500); await shot('location-unavailable-en');
  // Use only shipped controls to explicitly enter the bundled demo.
  await key('ArrowUp'); await key('Enter'); await shot('settings-en');
  await key('ArrowDown'); await key('Enter'); await shot('location-en');
  await key('ArrowUp'); await key('Enter'); await shot('demo-radar-en');
  await key('ArrowDown', 2); await key('Enter'); await shot('demo-nearest-en');
  await key('ArrowDown'); await key('Enter'); await shot('demo-highest-en', [20, 125, 420, 125]);
  await key('ArrowDown'); await key('Enter'); await shot('demo-detail-en'); await key('Backspace');
  for (const [locale, steps] of [['ja', 2], ['ko', 3], ['zh', 4], ['en', 1]]) {
    await key('Enter'); await key('ArrowDown', 3); await key('Enter');
    await key('ArrowDown', steps); await key('Enter'); await shot('language-' + locale, [20, 70, 420, 130]);
    await key('Backspace'); await key('Backspace'); await shot('demo-highest-' + locale, [20, 125, 420, 125]);
  }
  await key('Enter'); await key('Enter'); await shot('direction-en');
  await key('Backspace'); await key('Backspace');
  await page.evaluate(() => window.testView.setTarget('_current')); await page.waitForTimeout(350); await shot('demo-current-en');
  await page.evaluate(() => window.testView.blur()); await page.waitForTimeout(350);
  await page.evaluate(() => window.testView.focus()); await page.waitForTimeout(350);
  await page.reload(); await ready();
  // Actual pointer start before the 5-second countdown ends.
  await page.locator('canvas').click({ position: { x: 240, y: 220 } }); await page.waitForTimeout(500); await shot('pointer-start-en');
  let requests = 0, offline = false;
  const fixture = { elements: [
    { type: 'node', id: 9991, lat: 35.3606, lon: 138.7274, tags: { natural: 'peak', name: 'TEST summit', 'name:en': 'TEST very long mountain name with Unicode 山峰', ele: '3776' } },
    { type: 'node', id: 9992, lat: 35.401, lon: 138.8905, tags: { natural: 'peak', name: 'TEST unknown height' } }
  ] };
  await page.route(/https:\/\/overpass[^/]*\/api\/interpreter/, route => {
    requests++;
    return route.fulfill({ status: offline ? 503 : 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(fixture) });
  });
  await page.evaluate(() => {
    const view = window.testView;
    const mock = window.fieldMock = { watches: new Map(), sensors: new Map(), starts: 0, stops: 0 };
    function sensor(kind, vector) {
      return {
        start(request) {
          mock.starts++;
          const emit = () => view.hostCapabilitiesTarget.dispatchEvent(new CustomEvent(kind + '.reading', { detail: { ...request, timestamp: performance.now(), ...vector } }));
          mock.sensors.set(request.sessionId, setInterval(emit, 100));
        },
        stop(request) { mock.stops++; clearInterval(mock.sensors.get(request.sessionId)); mock.sensors.delete(request.sessionId); }
      };
    }
    view.setHostCapabilities({
      geolocation: {
        watchPosition(request) {
          const emit = () => view.hostCapabilitiesTarget.dispatchEvent(new CustomEvent('geolocation.position', { detail: { ...request,
            coords: { latitude: 35.22, longitude: 138.79, accuracy: 5, heading: 340, speed: 2 }, timestamp: Date.now() } }));
          mock.watches.set(request.watchId, setInterval(emit, 300));
        },
        clearWatch(request) { clearInterval(mock.watches.get(request.watchId)); mock.watches.delete(request.watchId); }
      },
      accelerometer: sensor('accelerometer', { x: 0, y: 0, z: 9.8 }),
      magnetometer: sensor('magnetometer', { x: 0.342, y: 0.94, z: 0 })
    });
    view.openBundle({ appId: 'peaknow-synthetic-field-test', files: window.testFiles, query: { locale: 'en' }, hostOptions: { initialTarget: '_blank' } });
  });
  await page.waitForTimeout(500);
  await page.locator('canvas').click({ position: { x: 240, y: 220 } });
  await page.waitForFunction(() => window.fieldMock.watches.size === 1 && window.fieldMock.sensors.size === 2);
  await page.waitForTimeout(1200); assert.equal(requests, 1); await shot('simulated-field-en', [20, 125, 420, 125]);
  await page.waitForTimeout(30000);
  offline = true;
  await key('ArrowUp', 2); await key('Enter'); await page.waitForTimeout(1200);
  assert.equal(requests, 3, 'offline refresh must try only two endpoints'); await shot('simulated-cached-offline-en', [20, 125, 420, 125]);
  await page.evaluate(() => window.testView.blur()); await page.waitForTimeout(350);
  assert.equal(await page.evaluate(() => window.fieldMock.watches.size), 0);
  assert.equal(await page.evaluate(() => window.fieldMock.sensors.size), 0);
  await page.evaluate(() => window.testView.focus()); await page.waitForTimeout(500);
  assert.equal(await page.evaluate(() => window.fieldMock.watches.size), 1);
  assert.equal(await page.evaluate(() => window.fieldMock.sensors.size), 2);
  assert.deepEqual(errors, []); assert.deepEqual(templateWarnings, []); assert.equal(serviceErrors.length, 2);
  console.log('Browser Ink checks passed: cover, auto/pointer start, three views, details, four languages, targets, simulated GPS/compass, HTTPS/cache/offline fallback and resource cleanup.');
  console.log('Screenshots use explicitly selected DEMO or labeled TEST fixtures; no physical device or Studio verification claim.');
} finally { await browser.close(); }
