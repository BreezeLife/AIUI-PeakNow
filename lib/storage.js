import { validArea } from './peaks.js';
export const PREFS = 'peaknow.preferences.v1', CACHE = 'peaknow.areas.v1';
export const defaults = { locale: 'en', radius: 50, minimum: 0, headingMode: 'auto', manual: null };
export function readStore(api, key, fallback) {
  try { const raw = api.getStorageSync(key); return raw ? JSON.parse(raw) : fallback; } catch (_) { return fallback; }
}
export function saveStore(api, key, value) {
  try { api.setStorageSync(key, JSON.stringify(value)); return true; } catch (_) { return false; }
}
export function preferences(raw) {
  return { locale: ['en', 'ja', 'ko', 'zh'].includes(raw?.locale) ? raw.locale : 'en', radius: [10, 25, 50, 100].includes(raw?.radius) ? raw.radius : 50,
    minimum: [0, 500, 1000, 2000].includes(raw?.minimum) ? raw.minimum : 0, headingMode: ['auto', 'gps', 'manual'].includes(raw?.headingMode) ? raw.headingMode : 'auto',
    manual: typeof raw?.manual === 'number' && Number.isFinite(raw.manual) && raw.manual >= 0 && raw.manual < 360 ? raw.manual : null };
}
export function readAreas(api) {
  const raw = readStore(api, CACHE, []); return Array.isArray(raw) ? raw.filter(validArea).slice(0, 3) : [];
}
