import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const output = path.resolve(process.env.PEAKNOW_OUTPUT || path.join(os.homedir(), '.codex/outputs/AIUI-PeakNow'));
const build = spawnSync(process.execPath, ['scripts/pack.mjs'], { cwd: root, stdio: 'inherit' });
if (build.status !== 0) process.exit(build.status || 1);
const html = path.join(output, 'peaknow-preview.html');
const command = process.env.AIX_BIN || 'npx';
const prefix = process.env.AIX_BIN ? [] : ['--yes', '--package', '@yodaos-pkg/aix-cli@0.8.2', 'aix'];
const preview = spawnSync(command, [...prefix, 'preview', path.join(output, 'peaknow.aix'), '--html-out', html], { cwd: root, stdio: 'inherit' });
if (preview.status !== 0) process.exit(preview.status || 1);
// Published CLI uses an unversioned SDK URL; pin the chosen runtime for preview.
fs.writeFileSync(html, fs.readFileSync(html, 'utf8').replace('https://esm.sh/@yodaos-pkg/ink"', 'https://esm.sh/@yodaos-pkg/ink@0.17.0"'));
const port = Number(process.env.PEAKNOW_PORT || 8776);
http.createServer((request, response) => {
  if (request.url !== '/' && request.url !== '/peaknow-preview.html') { response.writeHead(404); response.end(); return; }
  response.writeHead(200, { 'content-type': 'text/html; charset=utf-8' }); response.end(fs.readFileSync(html));
}).listen(port, '127.0.0.1', () => console.log(`AIUI 0.17.0 preview: http://127.0.0.1:${port}/peaknow-preview.html`));
