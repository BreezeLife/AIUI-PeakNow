import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const output = path.resolve(process.env.PEAKNOW_OUTPUT || path.join(os.homedir(), '.codex/outputs/AIUI-PeakNow'));
if (output === root || output.startsWith(root + path.sep)) throw Error('Output must be outside the Studio import root.');
fs.mkdirSync(output, { recursive: true });
const command = process.env.AIX_BIN || 'npx';
const prefix = process.env.AIX_BIN ? [] : ['--yes', '--package', '@yodaos-pkg/aix-cli@0.8.2', 'aix'];
function run(args) {
  const result = spawnSync(command, [...prefix, ...args], { cwd: root, encoding: 'utf8' });
  process.stdout.write(result.stdout || ''); process.stderr.write(result.stderr || '');
  if (result.error || result.status !== 0) throw result.error || Error(`AIX exited ${result.status}`);
  return result.stdout;
}
const help = run(['--help']);
if (!help.includes('aix pack') || !help.includes('aix list') || !help.includes('--engine')) throw Error('CLI lacks required commands');
const artifact = path.join(output, 'peaknow.aix');
const log = run(['pack', '.', '-o', artifact, '--engine', '0.17.0']);
const listing = run(['list', artifact]);
for (const required of ['app.json', 'app.js', 'AGENTS.md', 'LICENSE', 'pages/index/index.ink', 'assets/mountain.png', 'lib/runtime.js', 'lib/geo.js', 'lib/peaks.js', 'lib/heading.js', 'lib/storage.js', 'lib/i18n.js', 'lib/demo.js']) {
  if (!listing.includes(required)) throw Error(`Missing ${required}`);
}
if (/(?:\.git|\.aiui-evidence|node_modules|tests|docs|scripts)\//i.test(listing)) throw Error('Package contains development-only paths');
const sha256 = crypto.createHash('sha256').update(fs.readFileSync(artifact)).digest('hex');
fs.writeFileSync(path.join(output, 'peaknow.aix.sha256'), `${sha256}  peaknow.aix\n`);
fs.writeFileSync(path.join(output, 'pack.log'), help + log); fs.writeFileSync(path.join(output, 'list.txt'), listing);
console.log(JSON.stringify({ artifact, bytes: fs.statSync(artifact).size, sha256 }, null, 2));
