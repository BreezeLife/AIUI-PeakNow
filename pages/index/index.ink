<script def>
{
  "navigationBarTitleText": "Peak Now",
  "description": "Nearby named peaks with approximate direction, straight-line distance and summit elevation. Radar, nearest and highest views; offline area cache. Five-second cover or tap to start. English first, Japanese, Korean and Chinese selectable. Prefer _blank; compact _current supported. Not gaze-aligned AR.",
  "schema": {
    "data": {
      "type": "object",
      "properties": {
        "latitude": { "type": "number", "minimum": -90, "maximum": 90 },
        "longitude": { "type": "number", "minimum": -180, "maximum": 180 },
        "heading": { "type": "number", "minimum": 0, "maximum": 359.99 },
        "locale": { "type": "string", "enum": ["en", "ja", "ko", "zh"] }
      }
    }
  }
}
</script>

<script setup>
import wx from 'wx';
import { strings, countdownText, normalizeLocale } from '../../lib/i18n.js';
import { finite, validPoint, wrap, cardinal, buildRows, shortName } from '../../lib/geo.js';
import { CACHE_AGE, cacheCovers, fetchRadius } from '../../lib/peaks.js';
import { PREFS, CACHE, readStore, saveStore, preferences, readAreas } from '../../lib/storage.js';
import { Heading } from '../../lib/heading.js';
import { PeakRequest, FieldSession } from '../../lib/runtime.js';
import { DEMO_POINT, DEMO_PEAKS } from '../../lib/demo.js';

export default {
  data: {
    screen: 'splash', copy: strings('en'), locale: 'en', countdown: countdownText('en', 5), focus: 'start',
    mode: 'radar', effective: 'near', rows: [], actions: [], heading: '—', headingSource: strings('en').unknown,
    status: strings('en').noLocation, hint: strings('en').locationHint, notice: '', storageNote: '', areaLabel: '',
    positionLabel: '', rangeLabel: '50 km', minimumLabel: 'All heights', pageLabel: '0 / 0', emptyTitle: '',
    radar: false, leftLabel: '—', centerLabel: '—', rightLabel: '—', ticks: [], latInput: '', lonInput: '',
    directionMode: 'auto', manualLabel: '—', detailName: '', detailStats: '', detailBearing: '', screenTitle: '',
    row0: { visible: false, focused: false, shortName: '', stats: '', direction: '', volcano: false, action: '', number: '' }, tick0: { visible: false, x: 50, label: '' },
    row1: { visible: false, focused: false, shortName: '', stats: '', direction: '', volcano: false, action: '', number: '' }, tick1: { visible: false, x: 50, label: '' },
    row2: { visible: false, focused: false, shortName: '', stats: '', direction: '', volcano: false, action: '', number: '' }, tick2: { visible: false, x: 50, label: '' },
    action0: { visible: false, id: '', label: '', focused: false },
    action1: { visible: false, id: '', label: '', focused: false },
    action2: { visible: false, id: '', label: '', focused: false },
    action3: { visible: false, id: '', label: '', focused: false },
    action4: { visible: false, id: '', label: '', focused: false },
    action5: { visible: false, id: '', label: '', focused: false },
  },
  onLoad(query = {}) {
    this._visible = false; this._focused = true; this._dead = false; this._lastAction = -Infinity;
    this._remaining = 5000; this._countdownTimer = null; this._startedAt = null; this._tick = null;
    this._prefs = preferences(readStore(wx, PREFS, {})); this._areas = readAreas(wx); this._area = null;
    this._point = null; this._pointKind = ''; this._status = 'noLocation'; this._page = 0;
    this._loading = false; this._nextRequest = 0; this._lastPaint = 0; this._returnScreen = 'main';
    this._heading = new Heading(); this._request = new PeakRequest(wx);
    this._field = new FieldSession(typeof navigator !== 'undefined' ? navigator.geolocation : null,
      { acc: () => new Accelerometer({ frequency: 10 }), mag: () => new Magnetometer({ frequency: 10 }) },
      { fix: (coords, now) => this._fix(coords, now), compass: (degrees, now) => this._compass(degrees, now),
        sensorError: () => { this._heading.compass = null; this._render(); }, error: code => this._locationError(code) });
    if (query.locale) this._prefs.locale = normalizeLocale(query.locale);
    const parse = value => typeof value === 'number' ? value : typeof value === 'string' && value.trim() ? Number(value) : null;
    const point = { latitude: parse(query.latitude), longitude: parse(query.longitude) };
    if (validPoint(point)) { this._point = point; this._pointKind = 'manual'; }
    const heading = parse(query.heading);
    if (finite(heading) && heading >= 0 && heading < 360) { this._prefs.manual = heading; this._prefs.headingMode = 'manual'; }
    this._render();
  },
  onShow() { if (!this._dead) { this._visible = true; this._resume(); } },
  onHide() { this._visible = false; this._suspend(); },
  onUnload() { this._dead = true; this._visible = false; this._suspend(); },
  onHostFocus() { if (!this._dead) { this._focused = true; this._resume(); } },
  onHostBlur() { this._focused = false; this._suspend(); },
  _active() { return this._visible && this._focused && !this._dead; },
  _accept(event) {
    if (event && typeof event.stopPropagation === 'function') event.stopPropagation();
    if (!this._active() || Date.now() - this._lastAction < 300) return false;
    this._lastAction = Date.now(); return true;
  },
  _resume() {
    if (!this._active()) return;
    if (this.data.screen === 'splash') { this._startCountdown(); return; }
    if (this.data.screen !== 'main' || this._tick !== null) return;
    this._startField();
    this._loadArea(false);
    this._tick = setInterval(() => this._render(), 1000);
  },
  _startField() {
    if (this._pointKind === 'demo') return;
    if (!this._point) this._status = 'locating';
    this._field.start({ gps: !this._point || this._pointKind === 'gps', compass: this._prefs.headingMode === 'auto' });
    this._render();
  },
  _suspend() {
    this._pauseCountdown();
    if (this._tick != null) clearInterval(this._tick); this._tick = null;
    if (this._field) this._field.stop(); if (this._request) this._request.cancel();
    if (this._heading) this._heading.clear();
    if (this._loading) this._status = this._area ? 'cached' : 'ready'; this._loading = false;
  },
  _startCountdown() {
    if (this._countdownTimer !== null) return;
    this._startedAt = Date.now();
    this._countdownTimer = setInterval(() => {
      if (!this._active() || this.data.screen !== 'splash') return;
      const left = Math.max(0, this._remaining - Date.now() + this._startedAt);
      this.setData({ countdown: countdownText(this._prefs.locale, Math.ceil(left / 1000)) });
      if (!left) this._enter();
    }, 100);
  },
  _pauseCountdown() {
    if (this._startedAt != null) this._remaining = Math.max(0, this._remaining - Date.now() + this._startedAt);
    this._startedAt = null;
    if (this._countdownTimer != null) clearInterval(this._countdownTimer); this._countdownTimer = null;
  },
  start(event) { if (this._accept(event) && this.data.screen === 'splash') this._enter(); },
  _enter() {
    if (!this._active() || this.data.screen !== 'splash') return;
    this._pauseCountdown(); this._lastAction = Date.now();
    this.setData({ screen: 'main', focus: 'mode:radar' }); this._resume();
  },
  _fix(coords, now) {
    if (!this._active() || this.data.screen !== 'main') return;
    this._point = { latitude: coords.latitude, longitude: coords.longitude }; this._pointKind = 'gps';
    this._fixAt = now; this._accuracy = coords.accuracy;
    this._heading.acceptGPS(coords, now);
    if (!this._area || !cacheCovers(this._area, this._point, this._prefs.radius)) this._loadArea(false);
    else if (['locating', 'denied', 'unavailable', 'locationTimeout'].includes(this._status)) this._status = 'cached';
    this._render();
  },
  _compass(degrees, now) {
    if (!this._active() || this.data.screen !== 'main') return;
    this._heading.acceptCompass(degrees, now);
    if (now - this._lastPaint >= 250) { this._lastPaint = now; this._render(); }
  },
  _locationError(code) {
    if (!this._active() || this.data.screen !== 'main') return;
    this._heading.gps = null; this._status = code; this._render();
  },
  _loadArea(force) {
    if (!this._active() || this.data.screen !== 'main' || !this._point || this._pointKind === 'demo' || this._loading) return;
    if (!force) {
      const area = this._areas.find(value => cacheCovers(value, this._point, this._prefs.radius));
      if (area) { this._area = area; this._status = 'cached'; this._render(); return; }
      if (['offline', 'timeout', 'malformed'].includes(this._status)) return;
    }
    if (Date.now() < this._nextRequest) { this._render(); return; }
    if (this._area && !cacheCovers(this._area, this._point, this._prefs.radius)) this._area = null;
    this._loading = true; this._nextRequest = Date.now() + 30000; this._status = 'querying'; this._render();
    const point = { ...this._point };
    this._request.load(point, fetchRadius(this._prefs.radius), area => {
      if (!this._active() || this.data.screen !== 'main') return;
      this._loading = false; this._area = area; this._status = 'ready'; this._page = 0;
      this._areas = [area, ...this._areas.filter(old => !cacheCovers(old, point, this._prefs.radius))].slice(0, 3);
      this._saved = saveStore(wx, CACHE, this._areas); this._render();
    }, error => {
      if (!this._active() || this.data.screen !== 'main') return;
      this._loading = false; this._status = error; this._render();
    });
  },
  _save() {
    const value = this._pointKind === 'demo' && this._beforeDemo ? { ...this._prefs, ...this._beforeDemo } : this._prefs;
    this._saved = saveStore(wx, PREFS, value); this._render();
  },
  _open(screen) {
    if (this.data.screen === 'splash' || this.data.screen === 'main') this._returnScreen = this.data.screen;
    const heading = this._heading.value(this._prefs, Date.now()).degrees;
    if (heading !== null) this._snapshotHeading = heading;
    this._suspend(); this.setData({ screen, focus: screen === 'settings' ? 'direction' : 'back', notice: '' });
    this._render();
  },
  back(event) {
    if (!this._accept(event)) return;
    this._back();
  },
  _back() {
    const screen = this.data.screen;
    if (screen === 'main' || screen === 'splash') return;
    const destination = screen === 'detail' ? 'main' : screen === 'settings' || (screen === 'language' && this._returnScreen === 'splash') ? this._returnScreen : 'settings';
    this.setData({ screen: destination, focus: destination === 'main' ? 'settings' : destination === 'splash' ? 'language' : 'back', notice: '' });
    this._render(); this._resume();
  },
  action(event) {
    if (!this._accept(event)) return;
    const action = event?.currentTarget?.dataset?.action;
    if (action) this._activate(action);
  },
  _activate(action) {
    if (action === 'start') { this._enter(); return; }
    if (action === 'back') { this._back(); return; }
    if (['language', 'settings', 'direction', 'location', 'range'].includes(action)) { this._open(action); return; }
    if (action.startsWith('mode:') && this.data.screen === 'main') {
      this._page = 0; this.setData({ mode: action.slice(5), focus: action, notice: '' }); this._render(); return;
    }
    if (action.startsWith('locale:') && this.data.screen === 'language') {
      this._prefs.locale = normalizeLocale(action.slice(7)); this.setData({ focus: action }); this._save(); return;
    }
    if (action === 'next' || action === 'previous') { this._page += action === 'next' ? 1 : -1; this.setData({ focus: action }); this._render(); return; }
    if (action === 'refresh' && this.data.screen === 'main') {
      if (!this._point) { this._open('location'); return; }
      if (this._pointKind === 'demo') return;
      if (Date.now() < this._nextRequest) { this.setData({ notice: this.data.copy.cooldown }); return; }
      this.setData({ notice: '' }); this._loadArea(true); return;
    }
    if (action.startsWith('peak:') && this.data.screen === 'main') {
      const row = this._rows.find(value => value.id === Number(action.slice(5)));
      if (!row) return;
      this._open('detail'); this.setData({ detailName: shortName(row.name, this._prefs.locale === 'en' ? 60 : 34), detailStats: row.stats, detailBearing: row.direction }); return;
    }
    if (action === 'clear' && this.data.screen === 'settings') {
      this._areas = []; this._area = null; this._saved = saveStore(wx, CACHE, []);
      if (this._pointKind === 'demo') this._area = { peaks: DEMO_PEAKS, savedAt: Date.now() };
      this.setData({ notice: this.data.copy.erased }); this._render(); return;
    }
    if (this.data.screen === 'direction') {
      const current = this._heading.value(this._prefs, Date.now()).degrees ?? this._snapshotHeading;
      if (action === 'autoMode' || action === 'gpsMode') this._prefs.headingMode = action === 'autoMode' ? 'auto' : 'gps';
      else if (['turnLeft', 'turnRight', 'north'].includes(action)) {
        const base = this._prefs.headingMode === 'manual' ? this._prefs.manual : current;
        this._prefs.manual = action === 'north' ? 0 : wrap((base ?? 0) + (action === 'turnLeft' ? -15 : 15));
        this._prefs.headingMode = 'manual';
      } else return;
      this.setData({ focus: action }); this._save(); return;
    }
    if (this.data.screen === 'range') {
      const choices = action === 'radius' ? [10, 25, 50, 100] : [0, 500, 1000, 2000];
      const key = action === 'radius' ? 'radius' : 'minimum'; this._prefs[key] = choices[(choices.indexOf(this._prefs[key]) + 1) % choices.length];
      if (key === 'radius') this._status = 'ready';
      this._page = 0; this.setData({ focus: action }); this._save(); return;
    }
    if (this.data.screen === 'location') {
      if (this._pointKind === 'demo' && action !== 'demo' && this._beforeDemo) {
        this._prefs.headingMode = this._beforeDemo.headingMode; this._prefs.manual = this._beforeDemo.manual;
      }
      if (action === 'locate') {
        this._point = null; this._pointKind = ''; this._area = null; this._status = 'locating';
      } else if (action === 'demo') {
        if (this._pointKind !== 'demo') this._beforeDemo = { headingMode: this._prefs.headingMode, manual: this._prefs.manual };
        this._point = { ...DEMO_POINT }; this._pointKind = 'demo'; this._status = 'ready';
        this._area = { peaks: DEMO_PEAKS, savedAt: Date.now() }; this._prefs.headingMode = 'manual'; this._prefs.manual = 340;
      } else if (action === 'apply') {
        const lat = this.data.latInput.trim(), lon = this.data.lonInput.trim();
        const point = { latitude: lat ? Number(lat) : null, longitude: lon ? Number(lon) : null };
        if (!validPoint(point)) { this.setData({ notice: this.data.copy.invalid }); return; }
        this._point = point; this._pointKind = 'manual'; this._area = null; this._status = 'ready';
      } else return;
      this._page = 0; this._nextRequest = 0; this.setData({ screen: 'main', focus: 'settings', notice: '' }); this._render(); this._resume();
    }
  },
  latInput(event) { this.setData({ latInput: String(event?.detail?.value ?? event?.currentTarget?.value ?? '').slice(0, 16) }); },
  lonInput(event) { this.setData({ lonInput: String(event?.detail?.value ?? event?.currentTarget?.value ?? '').slice(0, 16) }); },
  focusAction(event) {
    if (this._active()) { this.setData({ focus: event?.currentTarget?.dataset?.action || this.data.focus }); this._render(); }
  },
  _choices() {
    if (this.data.screen === 'splash') return ['start', 'language'];
    if (this.data.screen === 'main') return ['mode:radar', 'mode:near', 'mode:high', ...this.data.rows.map(row => 'peak:' + row.id), 'previous', 'next', 'refresh', 'settings'];
    return this.data.actions.map(action => action.id);
  },
  onKeyUp(event) {
    if (!event || !this._active()) return;
    if (event.code === 'Backspace' && !['main', 'splash'].includes(this.data.screen)) {
      if (typeof event.preventDefault === 'function') event.preventDefault(); this.back(); return;
    }
    if (event.code === 'ArrowUp' || event.code === 'ArrowDown') {
      const choices = this._choices(), index = Math.max(0, choices.indexOf(this.data.focus));
      if (typeof event.preventDefault === 'function') event.preventDefault();
      this.setData({ focus: choices[(index + (event.code === 'ArrowDown' ? 1 : choices.length - 1)) % choices.length] }); this._render(); return;
    }
    if (event.code === 'Enter') {
      if (typeof event.preventDefault === 'function') event.preventDefault();
      if (this._accept()) this._activate(this.data.focus);
    }
  },
  _render() {
    if (this._dead || !this._prefs) return;
    const locale = this._prefs.locale, copy = strings(locale), now = Date.now(), heading = this._heading.value(this._prefs, now);
    const effective = this.data.mode === 'radar' && heading.degrees === null ? 'near' : this.data.mode;
    const covered = this._pointKind === 'demo' || this._area && this._point && cacheCovers(this._area, this._point, this._prefs.radius);
    const rows = buildRows(covered ? this._area?.peaks || [] : [], this._point, { ...this._prefs, heading: heading.degrees, mode: effective });
    const relative = value => value === null ? '' : Math.abs(value) < 5 ? copy.ahead : `${value < 0 ? copy.left : copy.right} ${Math.round(Math.abs(value))}°`;
    for (const row of rows) {
      row.shortName = shortName(row.name, 26);
      row.stats = `${row.distance < 10 ? row.distance.toFixed(1) : Math.round(row.distance)} km  /  ${row.elevation === null ? copy.unknownHeight : Math.round(row.elevation) + ' m'}`;
      row.direction = `${cardinal(row.bearing)} ${Math.round(row.bearing)}°${row.relative === null ? '' : ' · ' + relative(row.relative)}`;
      row.focused = this.data.focus === 'peak:' + row.id;
    }
    this._rows = rows; const pages = Math.ceil(rows.length / 3); this._page = Math.max(0, Math.min(this._page, Math.max(0, pages - 1)));
    const pageRows = rows.slice(this._page * 3, this._page * 3 + 3);
    const age = this._area ? Math.max(0, Math.floor((now - this._area.savedAt) / 86400000)) : 0;
    const areaLabel = this._pointKind === 'demo' ? copy.demoLabel : covered && this._area ? `${now - this._area.savedAt > CACHE_AGE ? copy.stale : copy.cached} ${age}${copy.age}${this._area.partial ? ' · ' + copy.partial : ''}` : '';
    const gpsOld = this._pointKind === 'gps' && now - this._fixAt > 30000;
    const status = gpsOld ? copy.moving : copy[this._status] || copy.ready;
    const failure = ['offline', 'timeout', 'malformed', 'denied', 'unavailable', 'locationTimeout'].includes(this._status);
    const hint = !this._point ? copy.locationHint : failure ? copy[this._status] : gpsOld ? copy.moving : this.data.mode === 'radar' && heading.degrees === null ? copy.noHeading : !rows.length && covered ? copy.emptyHint : !covered && !this._loading ? copy.offline : copy.uncertainty;
    const positionLabel = this._point ? `${this._pointKind === 'demo' ? copy.demoLabel : this._pointKind === 'gps' ? copy.gpsLocation : copy.manualLocation} · ${this._point.latitude.toFixed(3)}, ${this._point.longitude.toFixed(3)}` : copy.noLocation;
    const actions = [], push = (id, label) => actions.push({ id, label });
    const screen = this.data.screen;
    if (screen === 'settings') { for (const key of ['direction', 'location', 'range', 'language', 'clear', 'back']) push(key, copy[key]); }
    if (screen === 'language') { push('locale:en', (locale === 'en' ? '● ' : '') + 'English'); push('locale:ja', (locale === 'ja' ? '● ' : '') + '日本語'); push('locale:ko', (locale === 'ko' ? '● ' : '') + '한국어'); push('locale:zh', (locale === 'zh' ? '● ' : '') + '中文'); push('back', copy.back); }
    if (screen === 'direction') { for (const key of ['autoMode', 'gpsMode', 'turnLeft', 'turnRight', 'north', 'back']) push(key, copy[key]); }
    if (screen === 'location') { for (const key of ['locate', 'apply', 'demo', 'back']) push(key, copy[key]); }
    if (screen === 'range') { push('radius', copy.radius + ': ' + this._prefs.radius + ' km'); push('minimum', copy.minimum + ': ' + (this._prefs.minimum ? this._prefs.minimum + ' m' : copy.all)); push('back', copy.back); }
    if (screen === 'detail') push('back', copy.back);
    for (const action of actions) action.focused = this.data.focus === action.id;
    const slots = {};
    for (let i = 0; i < 3; i++) {
      const row = pageRows[i];
      slots['row' + i] = row ? { ...row, visible: true, action: 'peak:' + row.id, number: i + 1 } : { visible: false, focused: false, shortName: '', stats: '', direction: '', volcano: false, action: '', number: '' };
      slots['tick' + i] = row && row.relative !== null ? { visible: true, x: (row.relative + 45) / 90 * 100, label: String(i + 1) } : { visible: false, x: 50, label: '' };
    }
    for (let i = 0; i < 6; i++) slots['action' + i] = actions[i] ? { ...actions[i], visible: true } : { visible: false, id: '', label: '', focused: false };
    this.setData({ ...slots, copy, locale, countdown: countdownText(locale, Math.ceil(this._remaining / 1000)), effective, rows: pageRows, actions,
      heading: heading.degrees === null ? '—' : `${cardinal(heading.degrees)} ${Math.round(heading.degrees)}°`, headingSource: copy[heading.source],
      status, hint, areaLabel, positionLabel, storageNote: this._saved === false ? copy.storage : '', rangeLabel: this._prefs.radius + ' km', minimumLabel: this._prefs.minimum ? this._prefs.minimum + ' m' : copy.all,
      pageLabel: pages ? `${this._page + 1} / ${pages}` : '0 / 0', emptyTitle: !this._point ? copy.noLocation : this._loading ? copy.querying : !covered ? status : effective === 'radar' ? copy.noFront : copy.empty,
      radar: effective === 'radar' && heading.degrees !== null, ticks: pageRows.filter(row => row.relative !== null).map((row, index) => ({ id: row.id, x: (row.relative + 45) / 90 * 100, label: String(index + 1) })),
      leftLabel: heading.degrees === null ? '—' : `${cardinal(wrap(heading.degrees - 45))} −45°`, centerLabel: heading.degrees === null ? '—' : cardinal(heading.degrees), rightLabel: heading.degrees === null ? '—' : `${cardinal(wrap(heading.degrees + 45))} +45°`,
      directionMode: this._prefs.headingMode, manualLabel: this._prefs.manual === null ? '—' : `${cardinal(this._prefs.manual)} ${Math.round(this._prefs.manual)}°`, screenTitle: screen === 'detail' ? copy.detail : copy[screen] || '',
    });
  },
};
</script>

<page>
  <view class="shell">
    <view ink:if="{{screen === 'splash'}}" class="screen splash hidden-{{screen !== 'splash'}}">
      <view class="topline"><text class="edition">FIELD NOTES / 01</text><button class="small focus-{{focus === 'language'}}" data-action="language" bindtap="action" bindfocus="focusAction">EN / 日 / 한 / 中</button></view>
      <view class="cover" bindtap="start">
        <view class="brand"><image class="mountain" src="/assets/mountain.png" mode="aspectFit" /><text class="wordmark">PEAK NOW.</text></view>
        <text class="tagline">{{copy.tagline}}</text>
        <button class="start focus-{{focus === 'start'}}" data-action="start" bindtap="action" bindfocus="focusAction">{{copy.start}}</button>
        <text class="countdown">{{countdown}}</text>
      </view>
      <text class="scope">{{copy.scope}}</text>
    </view>

    <view ink:if="{{screen === 'main'}}" class="screen main hidden-{{screen !== 'main'}}">
      <view class="topline"><text class="title">PEAK NOW</text><text class="heading">{{heading}}</text><button class="small focus-{{focus === 'settings'}}" data-action="settings" bindtap="action" bindfocus="focusAction">{{copy.settings}}</button></view>
      <view class="tabs">
        <button class="tab selected-{{mode === 'radar'}} focus-{{focus === 'mode:radar'}}" data-action="mode:radar" bindtap="action" bindfocus="focusAction">{{mode === 'radar' ? '● ' : ''}}{{copy.radar}}</button>
        <button class="tab selected-{{mode === 'near'}} focus-{{focus === 'mode:near'}}" data-action="mode:near" bindtap="action" bindfocus="focusAction">{{mode === 'near' ? '● ' : ''}}{{copy.near}}</button>
        <button class="tab selected-{{mode === 'high'}} focus-{{focus === 'mode:high'}}" data-action="mode:high" bindtap="action" bindfocus="focusAction">{{mode === 'high' ? '● ' : ''}}{{copy.high}}</button>
        <text class="range-label">{{rangeLabel}}</text>
      </view>
      <view class="source-row"><text>{{headingSource}}</text><text>{{areaLabel || status}}</text></view>
      <view ink:if="{{radar}}" class="ruler hidden-{{!radar}}">
        <view class="ruler-line"></view><view class="center-tick"></view>
        <view ink:if="{{tick0.visible}}" class="peak-tick hidden-{{!tick0.visible}}" style="left: {{tick0.x}}%;"><text class="tick-label">{{tick0.label}}</text><view class="tick-stem"></view></view>
        <view ink:if="{{tick1.visible}}" class="peak-tick hidden-{{!tick1.visible}}" style="left: {{tick1.x}}%;"><text class="tick-label">{{tick1.label}}</text><view class="tick-stem"></view></view>
        <view ink:if="{{tick2.visible}}" class="peak-tick hidden-{{!tick2.visible}}" style="left: {{tick2.x}}%;"><text class="tick-label">{{tick2.label}}</text><view class="tick-stem"></view></view>
        <view class="ruler-labels"><text>{{leftLabel}}</text><text>{{centerLabel}}</text><text>{{rightLabel}}</text></view>
      </view>
      <view class="results">
        <button ink:if="{{row0.visible}}" class="peak-row focus-{{row0.focused}} hidden-{{!row0.visible}}" data-action="{{row0.action}}" bindtap="action" bindfocus="focusAction">
          <text class="peak-number">{{row0.number}}</text><view class="peak-info"><text class="peak-name">{{row0.volcano ? '△ ' : ''}}{{row0.shortName}}</text><text class="peak-stats">{{row0.stats}}</text></view><text class="peak-direction">{{row0.direction}}</text>
        </button>
        <button ink:if="{{row1.visible}}" class="peak-row focus-{{row1.focused}} hidden-{{!row1.visible}}" data-action="{{row1.action}}" bindtap="action" bindfocus="focusAction">
          <text class="peak-number">{{row1.number}}</text><view class="peak-info"><text class="peak-name">{{row1.volcano ? '△ ' : ''}}{{row1.shortName}}</text><text class="peak-stats">{{row1.stats}}</text></view><text class="peak-direction">{{row1.direction}}</text>
        </button>
        <button ink:if="{{row2.visible}}" class="peak-row focus-{{row2.focused}} hidden-{{!row2.visible}}" data-action="{{row2.action}}" bindtap="action" bindfocus="focusAction">
          <text class="peak-number">{{row2.number}}</text><view class="peak-info"><text class="peak-name">{{row2.volcano ? '△ ' : ''}}{{row2.shortName}}</text><text class="peak-stats">{{row2.stats}}</text></view><text class="peak-direction">{{row2.direction}}</text>
        </button>
        <view ink:if="{{!rows.length}}" class="empty hidden-{{rows.length > 0}}"><text class="empty-title">{{emptyTitle}}</text><text class="empty-hint">{{hint}}</text></view>
      </view>
      <view class="footer-actions"><button class="page-button focus-{{focus === 'previous'}}" data-action="previous" bindtap="action" bindfocus="focusAction">{{copy.previous}}</button><text class="page-label">{{pageLabel}}</text><button class="page-button focus-{{focus === 'next'}}" data-action="next" bindtap="action" bindfocus="focusAction">{{copy.next}}</button><button class="refresh focus-{{focus === 'refresh'}}" data-action="refresh" bindtap="action" bindfocus="focusAction">{{copy.refresh}}</button></view>
      <text class="feedback">{{storageNote || notice || (rows.length ? hint : status)}}</text>
      <text class="scope">{{copy.scope}}</text>
    </view>

    <view ink:if="{{screen !== 'splash' && screen !== 'main'}}" class="screen settings hidden-{{screen === 'splash' || screen === 'main'}}">
      <view class="topline"><text class="settings-title">{{screenTitle}}</text><text class="edition">PEAK NOW</text></view>
      <text ink:if="{{screen === 'settings'}}" class="description hidden-{{screen !== 'settings'}}">{{positionLabel}}</text>
      <text ink:if="{{screen === 'language'}}" class="description hidden-{{screen !== 'language'}}">{{copy.choose}}</text>
      <view ink:if="{{screen === 'direction'}}" class="direction-panel hidden-{{screen !== 'direction'}}"><text class="big-value">{{manualLabel}}</text><text class="description">{{directionMode === 'auto' ? copy.autoMode : directionMode === 'gps' ? copy.gpsMode : copy.manualMode}}</text><text class="description">{{copy.headingHint}}</text></view>
      <view ink:if="{{screen === 'location'}}" class="location-panel hidden-{{screen !== 'location'}}"><text class="description">{{copy.coordinateHint}}</text><view class="coordinate-row"><input value="{{latInput}}" placeholder="{{copy.lat}}" maxLength="16" bindinput="latInput" /><input value="{{lonInput}}" placeholder="{{copy.lon}}" maxLength="16" bindinput="lonInput" /></view></view>
      <view ink:if="{{screen === 'range'}}" class="range-panel hidden-{{screen !== 'range'}}"><text class="description">{{copy.cachedHint}}</text><text class="description">{{copy.about}}</text></view>
      <view ink:if="{{screen === 'detail'}}" class="detail-panel hidden-{{screen !== 'detail'}}"><text class="detail-name">{{detailName}}</text><text class="big-value">{{detailStats}}</text><text class="detail-bearing">{{detailBearing}}</text><text class="description">{{copy.origin}}</text><text class="description">{{copy.uncertainty}}</text></view>
      <view class="choices choices-{{screen}}">
        <button ink:if="{{action0.visible}}" class="choice focus-{{action0.focused}} hidden-{{!action0.visible}}" data-action="{{action0.id}}" bindtap="action" bindfocus="focusAction">{{action0.label}}</button>
        <button ink:if="{{action1.visible}}" class="choice focus-{{action1.focused}} hidden-{{!action1.visible}}" data-action="{{action1.id}}" bindtap="action" bindfocus="focusAction">{{action1.label}}</button>
        <button ink:if="{{action2.visible}}" class="choice focus-{{action2.focused}} hidden-{{!action2.visible}}" data-action="{{action2.id}}" bindtap="action" bindfocus="focusAction">{{action2.label}}</button>
        <button ink:if="{{action3.visible}}" class="choice focus-{{action3.focused}} hidden-{{!action3.visible}}" data-action="{{action3.id}}" bindtap="action" bindfocus="focusAction">{{action3.label}}</button>
        <button ink:if="{{action4.visible}}" class="choice focus-{{action4.focused}} hidden-{{!action4.visible}}" data-action="{{action4.id}}" bindtap="action" bindfocus="focusAction">{{action4.label}}</button>
        <button ink:if="{{action5.visible}}" class="choice focus-{{action5.focused}} hidden-{{!action5.visible}}" data-action="{{action5.id}}" bindtap="action" bindfocus="focusAction">{{action5.label}}</button>
      </view>
      <text class="feedback">{{storageNote || notice}}</text><text class="scope settings-scope">{{copy.scope}}</text>
    </view>
  </view>
</page>

<style>
.shell { width: 100%; height: 100%; padding: 12px 16px; box-sizing: border-box; background-color: #000000; color: #b8ffc3; font-family: sans-serif; }
.screen { width: 100%; height: 100%; display: flex; flex-direction: column; }
.topline { height: 30px; display: flex; flex-direction: row; justify-content: space-between; align-items: center; flex-shrink: 0; }
.edition { font-size: 11px; line-height: 16px; letter-spacing: 1px; }
button { color: #b8ffc3; background-color: #000000; border: 1px solid rgba(64,255,94,0.35); border-radius: 4px; margin: 0; box-sizing: border-box; display: flex; justify-content: center; align-items: center; }
.small { min-width: 74px; height: 28px; padding: 0 9px; font-size: 12px; line-height: 18px; }
.cover { flex: 1; display: flex; flex-direction: column; justify-content: center; align-items: center; }
.brand { display: flex; flex-direction: row; justify-content: center; align-items: center; }
.mountain { width: 72px; height: 55px; margin-right: 12px; }
.wordmark { color: #40ff5e; font-size: 38px; line-height: 50px; letter-spacing: -1px; font-weight: 700; }
.tagline { font-size: 14px; line-height: 20px; letter-spacing: 1px; margin-top: 10px; }
.start { color: #40ff5e; font-size: 22px; line-height: 28px; padding: 4px 20px; height: 42px; min-width: 210px; border-color: transparent; margin-top: 42px; }
.countdown { font-size: 12px; line-height: 18px; margin-top: 5px; }
.scope { font-size: 11px; line-height: 17px; text-align: center; flex-shrink: 0; }
.title { font-size: 16px; line-height: 22px; font-weight: 700; color: #40ff5e; }
.heading { font-size: 16px; line-height: 22px; color: #40ff5e; }
.tabs { height: 34px; margin-top: 6px; display: flex; flex-direction: row; align-items: center; flex-shrink: 0; }
.tab { height: 30px; padding: 0 12px; font-size: 14px; line-height: 20px; margin-right: 7px; }
.selected-true { color: #40ff5e; }.range-label { font-size: 12px; margin-left: auto; }
.source-row { height: 22px; font-size: 11px; line-height: 18px; display: flex; flex-direction: row; justify-content: space-between; flex-shrink: 0; }
.ruler { height: 45px; width: 92%; position: relative; margin-left: 4%; flex-shrink: 0; }
.ruler-line { position: absolute; top: 22px; width: 100%; height: 1px; background-color: rgba(64,255,94,0.5); }
.center-tick { position: absolute; left: 50%; top: 15px; height: 14px; width: 1px; background-color: #40ff5e; }
.peak-tick { position: absolute; top: 0; width: 12px; margin-left: -6px; display: flex; flex-direction: column; align-items: center; }
.tick-label { font-size: 11px; line-height: 14px; color: #40ff5e; }.tick-stem { height: 8px; width: 2px; background-color: #40ff5e; }
.ruler-labels { position: absolute; top: 28px; width: 100%; display: flex; flex-direction: row; justify-content: space-between; font-size: 10px; line-height: 14px; }
.results { flex: 1; min-height: 126px; display: flex; flex-direction: column; justify-content: center; }
.peak-row { height: 43px; width: 100%; flex-shrink: 0; border: 1px solid transparent; border-bottom: 1px solid rgba(64,255,94,0.2); display: flex; flex-direction: row; justify-content: flex-start; padding: 0 4px; }
.peak-number { width: 20px; font-size: 12px; }.peak-info { flex: 1; min-width: 0; display: flex; flex-direction: column; }
.peak-name { color: #40ff5e; font-size: 17px; line-height: 21px; }.peak-stats { font-size: 11px; line-height: 16px; }
.peak-direction { font-size: 11px; line-height: 16px; width: 120px; text-align: right; }
.empty { display: flex; flex-direction: column; justify-content: center; align-items: center; padding: 6px; }
.empty-title { color: #40ff5e; font-size: 20px; line-height: 28px; text-align: center; }.empty-hint { font-size: 13px; line-height: 20px; text-align: center; margin-top: 7px; }
.footer-actions { height: 32px; display: flex; flex-direction: row; align-items: center; flex-shrink: 0; }
.page-button { font-size: 12px; height: 28px; width: 70px; }.page-label { width: 60px; font-size: 12px; text-align: center; }.refresh { height: 28px; margin-left: auto; padding: 0 16px; font-size: 12px; }
.feedback { font-size: 11px; line-height: 16px; height: 20px; flex-shrink: 0; text-align: center; padding-top: 2px; }
.settings-title { font-size: 21px; line-height: 28px; color: #40ff5e; font-weight: 700; }
.description { font-size: 13px; line-height: 19px; margin-top: 5px; }.choices { display: flex; flex-direction: row; flex-wrap: wrap; margin-top: 12px; }
.choice { width: 48%; height: 40px; font-size: 16px; line-height: 22px; margin-right: 2%; margin-bottom: 9px; padding: 0 4px; }
.choices-language .choice { font-size: 21px; height: 47px; }.settings-scope { margin-top: auto; }
.big-value { font-size: 25px; line-height: 32px; color: #40ff5e; margin-top: 10px; }
.direction-panel, .location-panel, .range-panel, .detail-panel { display: flex; flex-direction: column; }
.coordinate-row { display: flex; flex-direction: row; margin-top: 14px; }
input { width: 48%; height: 34px; margin-right: 2%; font-size: 13px; color: #b8ffc3; background-color: #000000; border: 1px solid rgba(64,255,94,0.5); border-radius: 4px; padding: 4px; box-sizing: border-box; }
.detail-name { font-size: 25px; line-height: 32px; color: #40ff5e; margin-top: 20px; }.detail-bearing { font-size: 20px; line-height: 28px; margin-top: 10px; }
@media (target: _blank) { .shell { padding: 12px 16px; } }
@media (target: _current) {
  .shell { padding: 8px 12px; }.wordmark { font-size: 30px; line-height: 40px; }.mountain { width: 56px; height: 44px; }.start { margin-top: 25px; font-size: 19px; }
  .topline { height: 28px; }.ruler { height: 38px; }.results { min-height: 117px; }.peak-row { height: 39px; }.peak-name { font-size: 16px; }
  .scope { font-size: 10px; line-height: 15px; }.choice { height: 35px; margin-bottom: 7px; }.choices { margin-top: 8px; }.choices-language .choice { height: 42px; }
  .big-value { margin-top: 6px; font-size: 23px; }.description { font-size: 12px; line-height: 17px; }.tab { padding: 0 9px; }
}
.focus-true, button:focus { border: 2px solid #40ff5e; color: #40ff5e; background-color: rgba(64,255,94,0.08); }
.hidden-true { display: none; }
</style>
