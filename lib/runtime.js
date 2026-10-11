import { validPoint, finite } from './geo.js';
import { compassHeading } from './heading.js';
import { ENDPOINTS, parsePeaks, query, createArea } from './peaks.js';

export class PeakRequest {
  constructor(api) { this.api = api; this.generation = 0; this.task = null; this.timer = null; }
  cancel() {
    this.generation++;
    if (this.timer !== null) clearTimeout(this.timer); this.timer = null;
    const task = this.task; this.task = null;
    try { if (task) task.abort(); } catch (_) {}
  }
  load(point, radius, success, fail) {
    this.cancel(); const generation = this.generation;
    let index = 0;
    const attempt = () => {
      if (generation !== this.generation) return;
      let settled = false;
      const finish = (result, error) => {
        if (settled || generation !== this.generation) return;
        settled = true; if (this.timer !== null) clearTimeout(this.timer); this.timer = null; this.task = null;
        if (result) { success(result); return; }
        if (++index < ENDPOINTS.length) attempt(); else fail(error || 'offline');
      };
      this.timer = setTimeout(() => {
        const task = this.task; finish(null, 'timeout');
        try { if (task) task.abort(); } catch (_) {}
      }, 25000);
      try {
        const task = this.api.request({ url: ENDPOINTS[index], method: 'POST', timeout: 24000,
          header: { 'content-type': 'application/x-www-form-urlencoded' }, data: 'data=' + encodeURIComponent(query(point, radius)),
          success: response => {
            if (settled || generation !== this.generation) return;
            if (response.statusCode < 200 || response.statusCode >= 300) { finish(null, 'offline'); return; }
            try { const body = typeof response.data === 'string' ? JSON.parse(response.data) : response.data; finish(createArea(parsePeaks(body), point, radius)); }
            catch (_) { finish(null, 'malformed'); }
          },
          fail: error => finish(null, /timeout/i.test(error?.errMsg || '') ? 'timeout' : 'offline')
        });
        if (!settled && generation === this.generation) this.task = task;
      } catch (_) { finish(null, 'offline'); }
    };
    attempt();
  }
}

export class FieldSession {
  constructor(geo, sensors, callbacks) {
    this.geo = geo; this.sensors = sensors; this.callbacks = callbacks;
    this.generation = 0; this.watch = null; this.timer = null; this.owned = [];
  }
  stop() {
    this.generation++;
    if (this.timer !== null) clearTimeout(this.timer); this.timer = null;
    if (this.watch !== null) { try { this.geo.clearWatch(this.watch); } catch (_) {} this.watch = null; }
    this.stopSensors();
  }
  stopSensors() {
    for (const { sensor, reading, error } of this.owned) {
      try { sensor.removeEventListener('reading', reading); sensor.removeEventListener('error', error); sensor.stop(); } catch (_) {}
    }
    this.owned = [];
  }
  start({ gps = true, compass = true } = {}) {
    this.stop(); const generation = this.generation, current = () => generation === this.generation;
    if (gps) {
      let gotFix = false, disabled = false;
      const failed = error => {
        if (!current() || disabled) return;
        disabled = true;
        if (this.timer !== null) clearTimeout(this.timer); this.timer = null;
        if (this.watch !== null) { try { this.geo.clearWatch(this.watch); } catch (_) {} this.watch = null; }
        this.callbacks.error(error?.code === 1 ? 'denied' : error?.code === 3 ? 'locationTimeout' : 'unavailable');
      };
      const accept = position => {
        if (!current() || disabled) return;
        const coords = position?.coords;
        if (!validPoint(coords) || !finite(position.timestamp) || Math.abs(Date.now() - position.timestamp) > 30000) { failed(); return; }
        gotFix = true; if (this.timer !== null) clearTimeout(this.timer); this.timer = null;
        this.callbacks.fix(coords, position.timestamp);
      };
      this.timer = setTimeout(() => { if (!gotFix && current()) failed({ code: 3 }); }, 11000);
      try {
        if (!this.geo || typeof this.geo.watchPosition !== 'function') failed();
        else {
          const watch = this.geo.watchPosition(accept, failed, { enableHighAccuracy: true, timeout: 10000, maximumAge: 10000 });
          if (disabled) { try { this.geo.clearWatch(watch); } catch (_) {} } else this.watch = watch;
        }
      } catch (_) { failed(); }
    }
    if (compass) {
      let acc = null, mag = null, accAt = 0, magAt = 0, disabled = false;
      try {
        for (const kind of ['acc', 'mag']) {
          if (disabled) break;
          const sensor = this.sensors[kind]();
          const reading = () => {
            if (!current() || disabled) return;
            const vector = { x: sensor.x, y: sensor.y, z: sensor.z }, now = Date.now();
            if (kind === 'acc') { acc = vector; accAt = now; } else { mag = vector; magAt = now; }
            if (now - accAt > 1500 || now - magAt > 1500) return;
            const degrees = compassHeading(acc, mag);
            if (degrees !== null) this.callbacks.compass(degrees, now);
          };
          const error = () => {
            if (!current() || disabled) return;
            disabled = true; this.stopSensors(); this.callbacks.sensorError();
          };
          this.owned.push({ sensor, reading, error });
          sensor.addEventListener('reading', reading); sensor.addEventListener('error', error); sensor.start();
        }
      } catch (_) {
        disabled = true; this.stopSensors(); if (current()) this.callbacks.sensorError();
      }
    }
  }
}
