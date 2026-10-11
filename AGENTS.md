# Peak Now

English-first nearby mountain finder for Rokid Glasses, AIUI 0.17.0.
Import repository root. Open `pages/index/index`, preferably with `_blank`;
`_current` uses a compact layout. Japanese, Korean and Simplified Chinese are selectable.

Use the user's actual GPS position or explicitly supplied coordinates. Never
silently substitute demo coordinates. Optional Page data: latitude, longitude,
heading (true bearing, 0–359), locale (en/ja/ko/zh). Supplied heading is manual.
User intent may select radar, nearest, highest and settings inside the Page.

Peak data: OpenStreetMap named peaks/volcanoes via public Overpass HTTPS.
Request GEOLOCATION only after the cover enters the main Page. Prefer cache;
explicit refresh can update it. Persist language, range, filter, manual heading
and downloaded areas locally. No accounts, analytics or private API keys.

Directions use a host-exposed companion compass, current GPS course while moving,
or explicit manual bearing. A magnetic compass is approximate and may differ from
true north; GPS course is movement direction, not gaze. A sensor's existence does
not prove its origin or calibration. Verify the phone/host sensor mapping on device.
Never derive north from arbitrary glasses quaternion yaw. Never present radar marks
as scene-registered AR, visibility confirmation or safe navigation instructions.
Distances are straight-line great-circle distances, not trail lengths.
Elevation is OSM summit height, not the observer's altitude. Missing height is unknown.

Suspend requests, location watches, sensors and countdowns on hide/blur/unload.
Ignore late callbacks from previous sessions. Preserve host Back at the root.
Do not add Widgets or Agent Workers without an explicitly confirmed newer runtime.
Run deterministic tests, strict skill validation, AIX pack/list and browser preview.
Keep Studio/device checks and unregistered scanner policies blocked until evidenced.
