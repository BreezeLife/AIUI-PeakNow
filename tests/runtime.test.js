import test from 'node:test';
import assert from 'node:assert/strict';
import { FieldSession, PeakRequest } from '../lib/runtime.js';
import { DEMO_POINT } from '../lib/demo.js';

test('network mirrors are bounded and malformed data never becomes an empty success', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const calls = []; let result, failure;
  const request = new PeakRequest({ request(options) { calls.push(options); return { abort() {} }; } });
  request.load(DEMO_POINT, 60, v => { result = v; }, e => { failure = e; });
  calls[0].success({ statusCode: 200, data: { elements: [], remark: 'timeout' } });
  assert.equal(calls.length, 2);
  calls[1].success({ statusCode: 200, data: 'invalid JSON' });
  assert.equal(result, undefined); assert.equal(failure, 'malformed'); assert.equal(request.timer, null);
});
test('request cancellation aborts and ignores late delivery from an old location', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const calls = []; let count = 0, aborts = 0;
  const request = new PeakRequest({ request(options) { calls.push(options); return { abort() { aborts++; } }; } });
  request.load(DEMO_POINT, 60, () => count++, () => count++); request.cancel();
  calls[0].success({ statusCode: 200, data: { elements: [] } });
  t.mock.timers.tick(60000);
  assert.equal(count, 0); assert.equal(aborts, 1); assert.equal(calls.length, 1);
});
test('a silent network bridge times out twice and then stops', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let attempts = 0, aborts = 0, failure;
  const request = new PeakRequest({ request() { attempts++; return { abort() { aborts++; } }; } });
  request.load(DEMO_POINT, 60, () => assert.fail(), e => { failure = e; });
  t.mock.timers.tick(25000); t.mock.timers.tick(25000);
  assert.equal(attempts, 2); assert.equal(aborts, 2); assert.equal(failure, 'timeout');
});
test('field stop clears watches, listeners and sensors; late callbacks are ignored', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let geoCallback, cleared = 0, stopped = 0, fixes = 0, compasses = 0;
  const sensors = [];
  const factory = () => {
    const listeners = new Map(); const sensor = { x: 0, y: 1, z: 0, listeners,
      addEventListener(k, cb) { listeners.set(k, cb); }, removeEventListener(k) { listeners.delete(k); }, start() {}, stop() { stopped++; } };
    sensors.push(sensor); return sensor;
  };
  const field = new FieldSession({ watchPosition(cb) { geoCallback = cb; return 8; }, clearWatch(id) { assert.equal(id, 8); cleared++; } },
    { acc: factory, mag: factory }, { fix() { fixes++; }, compass() { compasses++; }, error() {}, sensorError() {} });
  field.start();
  geoCallback({ coords: { latitude: 35, longitude: 138, accuracy: 5 }, timestamp: Date.now() });
  sensors[0].z = 9.8; sensors[0].y = 0; sensors[0].listeners.get('reading')(); sensors[1].listeners.get('reading')();
  assert.equal(fixes, 1); assert.equal(compasses, 1);
  field.stop(); geoCallback({ coords: { latitude: 0, longitude: 0 }, timestamp: Date.now() });
  assert.equal(fixes, 1); assert.equal(stopped, 2); assert.equal(cleared, 1);
  assert.equal(sensors[0].listeners.size, 0); assert.equal(field.timer, null);
});
test('partial sensor setup is cleaned up and GPS continues as fallback', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let stopped = 0, errors = 0;
  const field = new FieldSession({ watchPosition() { return 3; }, clearWatch() {} },
    { acc: () => ({ addEventListener() {}, removeEventListener() {}, start() {}, stop() { stopped++; } }), mag: () => { throw Error('unsupported'); } },
    { fix() {}, compass() {}, error() {}, sensorError() { errors++; } });
  field.start(); assert.equal(errors, 1); assert.equal(stopped, 1); assert.equal(field.watch, 3); field.stop();
});
test('permission revocation stops the GPS watch and prevents late updates', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  let accept, reject, cleared = 0, fixes = 0, error;
  const field = new FieldSession({ watchPosition(a, b) { accept = a; reject = b; return 4; }, clearWatch() { cleared++; } }, {},
    { fix() { fixes++; }, error(code) { error = code; }, compass() {}, sensorError() {} });
  field.start({ compass: false }); reject({ code: 1 });
  accept({ coords: { latitude: 35, longitude: 138 }, timestamp: Date.now() });
  assert.equal(cleared, 1); assert.equal(fixes, 0); assert.equal(error, 'denied'); assert.equal(field.timer, null); field.stop();
});
