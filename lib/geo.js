export const finite = value => typeof value === 'number' && Number.isFinite(value);
export const wrap = value => finite(value) ? ((value % 360) + 360) % 360 : null;
export const delta = (bearing, heading) => wrap(bearing - heading + 180) - 180;
export const validPoint = p => !!p && finite(p.latitude) && finite(p.longitude) && Math.abs(p.latitude) <= 90 && Math.abs(p.longitude) <= 180;
const rad = degrees => degrees * Math.PI / 180;
export function distanceKm(a, b) {
  const dlat = rad(b.latitude - a.latitude), dlon = rad(b.longitude - a.longitude);
  const h = Math.sin(dlat / 2) ** 2 + Math.cos(rad(a.latitude)) * Math.cos(rad(b.latitude)) * Math.sin(dlon / 2) ** 2;
  return 6371.0088 * 2 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
}
export function bearingTo(a, b) {
  const dlon = rad(b.longitude - a.longitude), lat1 = rad(a.latitude), lat2 = rad(b.latitude);
  return wrap(Math.atan2(Math.sin(dlon) * Math.cos(lat2), Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dlon)) * 180 / Math.PI);
}
export function cardinal(value) {
  return finite(value) ? ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'][Math.round(wrap(value) / 45) % 8] : '—';
}
export function peakName(peak, locale) {
  return peak.names[locale] || peak.names.local || peak.names.en || Object.values(peak.names)[0] || '—';
}
export function buildRows(peaks, point, options) {
  if (!validPoint(point)) return [];
  const rows = peaks.map(peak => ({ ...peak, name: peakName(peak, options.locale), distance: distanceKm(point, peak), bearing: bearingTo(point, peak) }))
    .filter(row => row.distance <= options.radius && (options.minimum === 0 || finite(row.elevation) && row.elevation >= options.minimum));
  for (const row of rows) row.relative = finite(options.heading) ? delta(row.bearing, options.heading) : null;
  const mode = options.mode === 'radar' && !finite(options.heading) ? 'near' : options.mode;
  if (mode === 'radar') return rows.filter(row => Math.abs(row.relative) <= 45).sort((a, b) => Math.abs(a.relative) - Math.abs(b.relative) || a.distance - b.distance);
  return rows.sort(mode === 'high' ? (a, b) => (b.elevation ?? -Infinity) - (a.elevation ?? -Infinity) || a.distance - b.distance : (a, b) => a.distance - b.distance);
}
export function shortName(value, limit = 22) {
  const chars = Array.from(value);
  const width = char => /[\u0300-\u036f]/.test(char) ? 0 : /[^\x00-\x7f]/.test(char) ? 2 : /[MW@]/.test(char) ? 1.5 : /[il.,' ]/.test(char) ? 0.5 : 1;
  if (chars.reduce((total, char) => total + width(char), 0) <= limit) return value;
  let used = 0, result = '';
  for (const char of chars) { if (used + width(char) > limit - 1) break; result += char; used += width(char); }
  return result + '…';
}
