import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const file = new URL('../pages/index/index.ink', import.meta.url);
const script = fs.readFileSync(file, 'utf8').match(/<script setup>([\s\S]*?)<\/script>/)[1]
  .replace("import wx from 'wx';", 'const wx = globalThis.__peakTestWX;')
  .replace(/from '(\.\.\/\.\.\/lib\/[^']+)'/g, (_, relative) => `from '${new URL(relative, file).href}'`);
// Execute the shipped Page script, with only the host adapter replaced.
globalThis.__peakTestWX = {};
const definition = (await import('data:text/javascript;base64,' + Buffer.from(script).toString('base64'))).default;
function makePage(t, query = {}) {
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval', 'Date'], now: 1000000 });
  const store = new Map(), api = globalThis.__peakTestWX;
  api.getStorageSync = k => store.get(k); api.setStorageSync = (k, v) => store.set(k, v);
  api.request = () => ({ abort() {} });
  const page = { ...definition, data: structuredClone(definition.data), setData(values) { Object.assign(this.data, values); } };
  page.onLoad(query); page.onShow(); t.after(() => page.onUnload()); return { page, store };
}
function press(page, t, action) { t.mock.timers.tick(301); page.action({ currentTarget: { dataset: { action } }, stopPropagation() {} }); }
test('cover auto-start counts only active time and settings pauses the countdown', t => {
  const { page } = makePage(t);
  t.mock.timers.tick(2000); page.onHostBlur(); t.mock.timers.tick(20000);
  assert.equal(page.data.screen, 'splash'); page.onHostFocus(); t.mock.timers.tick(2900);
  assert.equal(page.data.screen, 'splash'); t.mock.timers.tick(200); assert.equal(page.data.screen, 'main');
});
test('host blur delivered before onLoad has no undefined timer cleanup', t => {
  const page = { ...definition, data: structuredClone(definition.data), setData(values) { Object.assign(this.data, values); } };
  t.mock.method(globalThis, 'clearInterval', handle => assert.notEqual(handle, undefined));
  assert.doesNotThrow(() => page.onHostBlur());
});
test('one tap starts once; unavailable GPS cannot silently create a demo location', t => {
  const { page } = makePage(t); press(page, t, 'start');
  assert.equal(page.data.screen, 'main'); assert.equal(page._point, null);
  page.start(); assert.equal(page._point, null); assert.equal(page.data.rows.length, 0);
});
test('explicit demo supports three views, details, language and manual heading', t => {
  const { page } = makePage(t); press(page, t, 'start'); press(page, t, 'settings'); press(page, t, 'location'); press(page, t, 'demo');
  assert.equal(page._pointKind, 'demo'); assert.match(page.data.areaLabel, /DEMO/);
  assert.equal(page.data.rows[0].name, 'Mount Fuji');
  press(page, t, 'mode:near'); const near = page.data.rows[0].name;
  press(page, t, 'mode:high'); assert.equal(page.data.rows[0].name, 'Mount Fuji'); assert.notEqual(near, 'Mount Fuji');
  press(page, t, 'peak:-1'); assert.equal(page.data.screen, 'detail'); assert.equal(page.data.detailName, 'Mount Fuji');
  press(page, t, 'back'); press(page, t, 'settings'); press(page, t, 'language'); press(page, t, 'locale:ja');
  assert.equal(page.data.locale, 'ja'); assert.equal(page.data.copy.start, 'タップして開始');
  press(page, t, 'back'); press(page, t, 'direction'); press(page, t, 'turnRight');
  assert.equal(page._prefs.manual, 355); assert.equal(page._prefs.headingMode, 'manual');
});
test('manual query validates numbers; keyboard ignores host Back at the root', t => {
  const { page } = makePage(t, { latitude: '35.22', longitude: '138.79', heading: '340', locale: 'ko' });
  assert.equal(page._pointKind, 'manual'); assert.equal(page.data.locale, 'ko'); assert.equal(page._prefs.manual, 340);
  press(page, t, 'start'); let prevented = 0;
  page.onKeyUp({ code: 'Backspace', preventDefault() { prevented++; } }); assert.equal(prevented, 0);
  press(page, t, 'settings'); t.mock.timers.tick(301);
  page.onKeyUp({ code: 'Backspace', preventDefault() { prevented++; } }); assert.equal(prevented, 1); assert.equal(page.data.screen, 'main');
});
test('unload cancels every retained timer and a late network callback', t => {
  const { page } = makePage(t, { latitude: 35.22, longitude: 138.79 });
  let options, aborts = 0; globalThis.__peakTestWX.request = o => { options = o; return { abort() { aborts++; } }; };
  press(page, t, 'start'); const snapshot = structuredClone(page.data); page.onUnload();
  options.success({ statusCode: 200, data: { elements: [] } }); t.mock.timers.tick(100000);
  assert.equal(aborts, 1); assert.equal(page._tick, null); assert.equal(page._request.timer, null); assert.deepEqual(page.data, snapshot);
});
test('cached peaks remain visible with an explicit failed refresh notice', t => {
  const { page } = makePage(t, { latitude: 35.22, longitude: 138.79 });
  press(page, t, 'start'); page._request.cancel(); page._loading = false;
  page._area = { schema: 1, center: page._point, radius: 60, savedAt: Date.now(), peaks: [{ id: 7, latitude: 35.3, longitude: 138.7, elevation: null, names: { en: 'Test summit' } }] };
  page._status = 'offline'; page._render();
  assert.equal(page.data.rows.length, 1); assert.match(page.data.hint, /Service unavailable/); assert.match(page.data.rows[0].stats, /Height unknown/);
});
test('cover language selection pauses auto-start and persists the choice', t => {
  const { page, store } = makePage(t); t.mock.timers.tick(1000); press(page, t, 'language');
  press(page, t, 'locale:zh'); t.mock.timers.tick(20000); assert.equal(page.data.screen, 'language');
  assert.equal(JSON.parse(store.get('peaknow.preferences.v1')).locale, 'zh');
  press(page, t, 'back'); assert.equal(page.data.screen, 'splash'); t.mock.timers.tick(4000); assert.equal(page.data.screen, 'main');
});
test('saving a language in demo mode cannot persist its artificial manual heading', t => {
  const { page, store } = makePage(t); press(page, t, 'start'); press(page, t, 'settings'); press(page, t, 'location'); press(page, t, 'demo');
  press(page, t, 'settings'); press(page, t, 'language'); press(page, t, 'locale:ko');
  const saved = JSON.parse(store.get('peaknow.preferences.v1'));
  assert.equal(saved.locale, 'ko'); assert.equal(saved.headingMode, 'auto'); assert.equal(saved.manual, null);
});
test('GPS updates do not retry a failed query indefinitely; Refresh owns recovery', t => {
  const { page } = makePage(t, { latitude: 35.22, longitude: 138.79 });
  let requests = 0; globalThis.__peakTestWX.request = () => { requests++; return { abort() {} }; };
  press(page, t, 'start'); page._request.cancel(); page._loading = false; page._status = 'offline';
  t.mock.timers.tick(60000);
  for (let i = 0; i < 10; i++) page._fix({ latitude: 35.22, longitude: 138.79, speed: 0, accuracy: 10 }, Date.now());
  assert.equal(requests, 1); press(page, t, 'refresh'); assert.equal(requests, 2);
});
