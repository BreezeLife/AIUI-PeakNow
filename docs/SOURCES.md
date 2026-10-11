# Inspected sources

Inspection date: 2026-10-12. Target: AIUI 0.17.0.

- Requested skill revision: `9cf54c1802fe978cc025d3f79d4ece45d0add773`.
  [SKILL.md](https://github.com/BreezeLife/rokid-aiui-agent-skill/blob/9cf54c1802fe978cc025d3f79d4ece45d0add773/skills/rokid-aiui-agent/SKILL.md).
- Canonical AIUI source: `v0.17.0`, `88e70bb0382525c1a93ef077c2401dcc31a273ce`.
- [Page API](https://github.com/yodaos-project/AIUI/blob/88e70bb0382525c1a93ef077c2401dcc31a273ce/documentation/3-api/framework/page.en-US.md),
  [focus](https://github.com/yodaos-project/AIUI/blob/88e70bb0382525c1a93ef077c2401dcc31a273ce/documentation/1-framework/open-agent-format/focus.en-US.md),
  [Page events](https://github.com/yodaos-project/AIUI/blob/88e70bb0382525c1a93ef077c2401dcc31a273ce/documentation/1-framework/open-agent-format/page-events.en-US.md),
  [target](https://github.com/yodaos-project/AIUI/blob/88e70bb0382525c1a93ef077c2401dcc31a273ce/documentation/1-framework/open-agent-format/target.en-US.md).
- [HTTPS API](https://github.com/yodaos-project/AIUI/blob/88e70bb0382525c1a93ef077c2401dcc31a273ce/documentation/3-api/network/https.en-US.md):
  wx.request with method, header, data, timeout, success/fail, RequestTask.abort.
- [Local storage](https://github.com/yodaos-project/AIUI/blob/88e70bb0382525c1a93ef077c2401dcc31a273ce/documentation/3-api/storage-api.en-US.md):
  wx.getStorageSync and wx.setStorageSync, with explicit JSON strings.
- [Geolocation sample](https://github.com/yodaos-project/AIUI/blob/88e70bb0382525c1a93ef077c2401dcc31a273ce/samples/capabilities/pages/geolocation/index.ink),
  [Navigator](https://github.com/yodaos-project/AIUI/blob/88e70bb0382525c1a93ef077c2401dcc31a273ce/documentation/3-api/navigator.en-US.md),
  [permission declaration](https://github.com/yodaos-project/AIUI/blob/88e70bb0382525c1a93ef077c2401dcc31a273ce/samples/capabilities/app.json):
  watchPosition / clearWatch, GEOLOCATION. Host origin and grants remain device gates.
- [Compass sample](https://github.com/yodaos-project/AIUI/blob/88e70bb0382525c1a93ef077c2401dcc31a273ce/samples/capabilities/pages/compass/index.ink),
  [Magnetometer sample](https://github.com/yodaos-project/AIUI/blob/88e70bb0382525c1a93ef077c2401dcc31a273ce/samples/capabilities/pages/magnetometer/index.ink),
  [Accelerometer](https://github.com/yodaos-project/AIUI/blob/88e70bb0382525c1a93ef077c2401dcc31a273ce/documentation/3-api/device/accelerometer.en-US.md):
  global constructors, reading/error listeners, start/stop, gravity/magnetic cross
  product heading. There is no separate Magnetometer documentation file in this
  snapshot. Capability detection and failure cleanup are required.
- [Input](https://github.com/yodaos-project/AIUI/blob/88e70bb0382525c1a93ef077c2401dcc31a273ce/documentation/2-components/input.en-US.md),
  [Image](https://github.com/yodaos-project/AIUI/blob/88e70bb0382525c1a93ef077c2401dcc31a273ce/documentation/2-components/image.en-US.md).
- Browser SDK: published `@yodaos-pkg/ink@0.17.0`; its host interfaces were inspected
  to provide synthetic geolocation and sensor events in the browser harness.
  Published AIX CLI 0.8.2 otherwise points preview to an unversioned SDK URL.
- Product reference: `kissyjpf/evenhub-peak-radar` at
  `7f5cf24e245749f37bd18a41b01f6b9a5e73a57e`, MIT. Read for view modes, Overpass data,
  area coverage and compass limitations; no source was copied.
- Requested cover reference: `nickustinov/paddle-even-g2/screenshot-splash.png`.
  Original Peak Now mountain linework was drawn for this project; reference bitmap
  and logo are not included.

The audit helper follows the user's adjacent Level Now project and uses the
requested skill's canonical contracts directly. Its generic registry conservatively
quarantines storage, timers, image/input, geolocation and other unregistered items;
source availability does not make those policy gates pass automatically.
