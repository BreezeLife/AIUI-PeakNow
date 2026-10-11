# Verification record

Target: AIUI 0.17.0. Local verification date: 2026-10-12.
Full-screen and compact layouts use a 480 × 352 logical canvas.

## Executed checks

- `npm test`: **26 passed**, including the shipped Page script, active-time cover,
  input deduplication, four complete language dictionaries, date-line geodesy,
  range/height sorting, malformed and partial data, unknown elevations, cache
  coverage, expired course, permission revocation, bounded mirrors, explicit retry,
  late-callback suppression and resource cleanup.
- Skill `validate_aiui_project.py . --target-version 0.17.0 --repository-root . --strict --json`:
  no errors or warnings.
- AIX CLI `@yodaos-pkg/aix-cli@0.8.2 --help` was executed before using its advertised
  pack/list/preview commands. Packaging uses `--engine 0.17.0`.
- `npm run pack`: successful package creation and exact listing verification.
  The package contains the manifest, App, Page, required libraries, original
  mountain mark and license; it excludes Git, audit captures, tests and documentation.
- Browser Ink harness: **passed** the complete four-language flow and synthetic
  GPS/compass, HTTPS, cache/offline fallback, focus return and resource cleanup.

Browser harness command after generating `peaknow-preview.html` from the AIX:

```sh
PLAYWRIGHT_MODULE=/path/to/playwright/index.mjs \
CHROME_BIN=/path/to/chrome \
PREVIEW_URL=http://127.0.0.1:8776/peaknow-preview.html \
node scripts/preview-check.mjs
```

The harness pins the published browser SDK to 0.17.0, uses actual Page controls,
checks cover/pointer start, sorting, details, language switching, target changes,
visible result regions and focus return. It supplies synthetic host GPS and
Accelerometer/Magnetometer events and controlled Overpass responses to verify
request integration, cached offline fallback and owned resource cleanup.

Two compatibility fixes came from the stable-runtime preview: early host blur can
arrive before onLoad, and changing keyed lists could leave rows visually absent.
Cleanup accepts uninitialized timer handles. The UI uses three explicit row slots
and six explicit action slots so sorting/reopening preserves visible content.

## Evidence boundaries

The required source-bound UX and per-capability matrices are generated in
[AIUI-AUDIT.md](../.aiui-evidence/AIUI-AUDIT.md). Local command logs, unit mocks and
browser captures do not meet the skill's independent RUNNER/STUDIO/DEVICE/SCOPE
attestation requirements. The conservative audit therefore keeps these layers
blocked and reports a preview build rather than a release-ready product.

Product-only claims explicitly cover the injected HTTPS, geolocation, compass and
local-cache adapters, even where the generic scanner cannot resolve their aliases.
Unregistered registry items remain one-to-one quarantine rows; none are silently
removed or declared to pass.

No authenticated AIUI Studio session or connected Rokid device was available.
Studio import, actual phone sensor origin/mounting, native permission delivery,
temple input, optical readability and endurance need the checks in
[DEVICE-ACCEPTANCE.md](DEVICE-ACCEPTANCE.md).

Public service probes during this session returned HTTP 406 from overpass-api.de
and HTTP 500 from overpass.kumi.systems. The extra osm.jp mirror suggested by the
reference had an expired TLS certificate and was not added. A successful real
mountain query was not observed here. Synthetic response tests cover the success
path; real service recovery remains a device/network acceptance check.

## Screenshots

All screenshots are browser Ink renders. `demo-*` images use the explicitly
selected Fuji fixture, not a live lookup. `simulated-*` images use visible TEST
summits and synthetic host events. The cover is the actual shipped UI. Screenshot
names identify locale, view and fixture provenance.
