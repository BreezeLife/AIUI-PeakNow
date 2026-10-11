import { finite, wrap, delta } from './geo.js';
export function compassHeading(acc, mag) {
  if (!acc || !mag || ![acc.x, acc.y, acc.z, mag.x, mag.y, mag.z].every(finite)) return null;
  const normalize = v => { const n = Math.hypot(v.x, v.y, v.z); return n > 1e-6 ? { x: v.x / n, y: v.y / n, z: v.z / n } : null; };
  const cross = (a, b) => ({ x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x });
  const gravity = normalize(acc), magnetic = normalize(mag);
  if (!gravity || !magnetic) return null;
  const east = normalize(cross(magnetic, gravity)); if (!east) return null;
  const north = normalize(cross(gravity, east)); if (!north) return null;
  return wrap(Math.atan2(-north.x, north.y) * 180 / Math.PI);
}
export class Heading {
  constructor() { this.compass = null; this.gps = null; }
  acceptCompass(degrees, now) {
    if (!finite(degrees)) return;
    const previous = this.compass;
    const value = previous && now - previous.at < 2500 ? wrap(previous.value + delta(degrees, previous.value) * 0.3) : wrap(degrees);
    this.compass = { value, at: now };
  }
  acceptGPS(coords, now) {
    if (finite(coords.heading) && coords.heading >= 0 && coords.heading < 360 && finite(coords.speed) && coords.speed >= 1.2 && finite(coords.accuracy) && coords.accuracy <= 50) this.gps = { value: wrap(coords.heading), at: now };
    else this.gps = null;
  }
  value(prefs, now) {
    if (prefs.headingMode === 'manual') return { degrees: prefs.manual, source: prefs.manual === null ? 'unknown' : 'manual' };
    if (prefs.headingMode === 'auto' && this.compass && now - this.compass.at <= 2500) return { degrees: this.compass.value, source: 'compass' };
    if (this.gps && now - this.gps.at <= 10000) return { degrees: this.gps.value, source: 'gps' };
    return { degrees: null, source: 'unknown' };
  }
  clear() { this.compass = null; this.gps = null; }
}
