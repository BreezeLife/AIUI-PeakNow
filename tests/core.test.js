import test from 'node:test';
import assert from 'node:assert/strict';
import { distanceKm, bearingTo, delta, buildRows, validPoint, shortName } from '../lib/geo.js';
import { elevation, parsePeaks, cacheCovers, createArea, validArea, query } from '../lib/peaks.js';
import { Heading, compassHeading } from '../lib/heading.js';
import { strings, LOCALES } from '../lib/i18n.js';
import { preferences, readAreas, saveStore } from '../lib/storage.js';
import { DEMO_POINT, DEMO_PEAKS } from '../lib/demo.js';

test('great-circle distance and initial bearing cross the date line', () => {
  const a = { latitude: 0, longitude: 179.9 }, b = { latitude: 0, longitude: -179.9 };
  assert.ok(Math.abs(distanceKm(a, b) - 22.239) < 0.01);
  assert.equal(bearingTo(a, b), 90); assert.equal(delta(1, 359), 2);
  assert.equal(delta(359, 1), -2); assert.equal(validPoint({ latitude: '', longitude: 0 }), false);
});
test('radar wraps north and rejects peaks behind the selected heading', () => {
  const rows = buildRows(DEMO_PEAKS, DEMO_POINT, { locale: 'en', radius: 50, minimum: 0, mode: 'radar', heading: 340 });
  assert.equal(rows[0].name, 'Mount Fuji'); assert.ok(rows.every(p => Math.abs(p.relative) <= 45));
  assert.ok(!rows.some(p => p.name === 'Mount Echizen'));
});
test('unknown heading falls back to nearest; highest puts unknown height last', () => {
  const unknown = { ...DEMO_PEAKS[0], id: 500, elevation: null };
  const options = { locale: 'ko', radius: 50, minimum: 0, mode: 'radar', heading: null };
  const rows = buildRows([...DEMO_PEAKS, unknown], DEMO_POINT, options);
  assert.ok(rows.every(p => p.relative === null));
  assert.ok(rows.every((p, i) => i === 0 || p.distance >= rows[i - 1].distance));
  const high = buildRows([...DEMO_PEAKS, unknown], DEMO_POINT, { ...options, mode: 'high' });
  assert.equal(high.at(-1).elevation, null); assert.equal(high[0].name, '후지산');
  assert.ok(!buildRows([unknown], DEMO_POINT, { ...options, minimum: 500 }).length);
});
test('elevation parses metres and feet and refuses ambiguous text', () => {
  assert.equal(elevation('3,776 m'), 3776); assert.equal(elevation('ca. 800'), 800);
  assert.ok(Math.abs(elevation('1000 ft') - 304.8) < 1e-6);
  for (const value of ['12;34', 'about 12?', 'summit 3776', '99999', NaN]) assert.equal(elevation(value), null);
});
const node = { type: 'node', id: 1, lat: 35.3, lon: 138.7, tags: { natural: 'peak', name: '富士山', 'name:en': 'Mount Fuji', ele: '3776' } };
test('Overpass parser rejects service remarks, malformed and all-invalid results', () => {
  for (const body of [{}, { elements: [], remark: 'runtime error' }, { elements: [{ type: 'way' }] }]) assert.throws(() => parsePeaks(body));
  assert.deepEqual(parsePeaks({ elements: [] }), { peaks: [], skipped: 0 });
  const result = parsePeaks({ elements: [node, node, { ...node, id: 2, lat: 999 }] });
  assert.equal(result.peaks.length, 1); assert.equal(result.skipped, 1);
  assert.equal(result.peaks[0].names.en, 'Mount Fuji');
});
test('cache coverage uses the entire requested disc, not just the center', () => {
  const area = createArea({ peaks: DEMO_PEAKS, skipped: 0 }, DEMO_POINT, 60, 1);
  assert.ok(validArea(area)); assert.ok(cacheCovers(area, DEMO_POINT, 50));
  assert.equal(cacheCovers(area, { latitude: 35.4, longitude: 138.79 }, 50), false);
  assert.equal(cacheCovers(area, DEMO_POINT, 100), false);
  assert.equal(validArea({ ...area, peaks: [{ ...DEMO_PEAKS[0], longitude: 999 }] }), false);
  assert.throws(() => query({ latitude: '35', longitude: 0 }, 50));
});
test('heading sources expire and stationary GPS course cannot masquerade as facing', () => {
  const h = new Heading(), prefs = { headingMode: 'auto', manual: 20 };
  h.acceptGPS({ heading: 80, speed: 2, accuracy: 10 }, 1000);
  h.acceptCompass(359, 1000); h.acceptCompass(1, 1100);
  assert.ok(h.value(prefs, 1200).degrees > 359); assert.equal(h.value(prefs, 1200).source, 'compass');
  assert.equal(h.value(prefs, 4000).source, 'gps');
  h.acceptGPS({ heading: 80, speed: 0, accuracy: 10 }, 5000);
  assert.equal(h.value(prefs, 5000).source, 'unknown');
  h.acceptGPS({ heading: 80, speed: 2, accuracy: 100 }, 6000);
  assert.equal(h.value(prefs, 6000).source, 'unknown');
  assert.equal(h.value({ ...prefs, headingMode: 'manual' }, 999999).degrees, 20);
  assert.equal(compassHeading({ x: 0, y: 0, z: 0 }, { x: 1, y: 0, z: 0 }), null);
  assert.equal(compassHeading({ x: 0, y: 0, z: 9.8 }, { x: 0, y: 1, z: 0 }), 0);
});
test('four languages have the same complete key set', () => {
  const keys = Object.keys(strings('en')).sort();
  for (const locale of LOCALES) { assert.deepEqual(Object.keys(strings(locale)).sort(), keys); assert.ok(Object.values(strings(locale)).every(Boolean)); }
  assert.equal(strings('bad').start, 'Tap to start');
});
test('corrupt settings and denied storage degrade without failure', () => {
  assert.equal(preferences({ locale: 'xx', manual: NaN }).locale, 'en');
  const api = { getStorageSync() { throw Error('denied'); }, setStorageSync() { throw Error('quota'); } };
  assert.deepEqual(readAreas(api), []); assert.equal(saveStore(api, 'test', {}), false);
});
test('long multilingual peak labels have a bounded display width', () => {
  assert.equal(shortName('Mount Fuji', 26), 'Mount Fuji');
  assert.ok(shortName('山'.repeat(40), 26).length <= 14);
  assert.ok(shortName('W'.repeat(80), 26).length <= 18);
  assert.ok(shortName('⛰'.repeat(40), 26).endsWith('…'));
});
