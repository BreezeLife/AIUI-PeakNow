import { finite, validPoint, distanceKm } from './geo.js';
export const ENDPOINTS = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter'];
export const CACHE_AGE = 30 * 24 * 60 * 60 * 1000;
export const MAX_PEAKS = 1600;
export function elevation(raw) {
  if (finite(raw)) return raw >= -500 && raw <= 9000 ? raw : null;
  if (typeof raw !== 'string') return null;
  const text = raw.trim().replace(/,/g, '');
  const m = text.match(/^(?:ca\.?\s*|~\s*)?(-?\d+(?:\.\d+)?)\s*(m|metres?|meters?|ft|feet)?$/i);
  if (!m) return null;
  const number = Number(m[1]) * (/^(ft|feet)$/i.test(m[2] || '') ? 0.3048 : 1);
  return number >= -500 && number <= 9000 ? number : null;
}
function cleanName(value) { return typeof value === 'string' ? Array.from(value.replace(/[\u0000-\u001f\u007f]/g, '').trim()).slice(0, 100).join('') : ''; }
export function parsePeaks(payload) {
  if (!payload || !Array.isArray(payload.elements) || payload.remark) throw Error('malformed');
  if (payload.elements.length > 30000) throw Error('too-large');
  const peaks = [], ids = new Set(); let skipped = 0;
  for (const node of payload.elements) {
    const tags = node.tags || {}, point = { latitude: node.lat, longitude: node.lon };
    if (node.type !== 'node' || !Number.isSafeInteger(node.id) || !validPoint(point) || !['peak', 'volcano'].includes(tags.natural)) { skipped++; continue; }
    const names = { local: cleanName(tags.name), en: cleanName(tags['name:en']), ja: cleanName(tags['name:ja']), ko: cleanName(tags['name:ko']), zh: cleanName(tags['name:zh']) };
    if (!Object.values(names).some(Boolean)) { skipped++; continue; }
    if (ids.has(node.id)) continue;
    ids.add(node.id); peaks.push({ id: node.id, ...point, elevation: elevation(tags.ele), names, volcano: tags.natural === 'volcano' });
  }
  if (payload.elements.length && !peaks.length) throw Error('malformed');
  return { peaks, skipped };
}
export function query(point, radius) {
  if (!validPoint(point) || !finite(radius) || radius < 1 || radius > 125) throw Error('invalid-query');
  const around = `around:${Math.round(radius * 1000)},${point.latitude.toFixed(6)},${point.longitude.toFixed(6)}`;
  return `[out:json][timeout:20];(node["natural"="peak"](${around});node["natural"="volcano"](${around}););out body;`;
}
export const fetchRadius = radius => radius + Math.min(25, radius * 0.2);
export function cacheCovers(area, point, radius) {
  return !!area && validPoint(point) && finite(radius) && validPoint(area.center) && finite(area.radius) && area.radius >= radius && distanceKm(area.center, point) <= area.radius - radius + 1e-6;
}
export function validArea(area) {
  return !!area && area.schema === 1 && validPoint(area.center) && finite(area.radius) && area.radius > 0 && area.radius <= 125 && finite(area.savedAt) && area.savedAt > 0 && area.savedAt <= Date.now() + 60000 && Array.isArray(area.peaks) && area.peaks.length <= MAX_PEAKS && area.peaks.every(p => validPoint(p) && Number.isSafeInteger(p.id) && (p.elevation === null || finite(p.elevation) && p.elevation >= -500 && p.elevation <= 9000) && p.names && Object.values(p.names).some(v => typeof v === 'string' && v.length > 0) && Object.values(p.names).every(v => typeof v === 'string' && v.length <= 200));
}
export function createArea(result, center, radius, now = Date.now()) {
  const ordered = result.peaks.slice().sort((a, b) => distanceKm(center, a) - distanceKm(center, b));
  return { schema: 1, center, radius, savedAt: now, peaks: ordered.slice(0, MAX_PEAKS), partial: result.skipped > 0 || ordered.length > MAX_PEAKS };
}
