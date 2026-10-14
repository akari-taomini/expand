const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const assert = require('node:assert/strict');
const script = path.resolve(__dirname, '../tavern-memory.cjs');
const root = fs.mkdtempSync(path.join(process.env.TAVERN_TEST_TMP || os.tmpdir(), 'memory-test-'));
let count = 0;
function fixture(content) {
  const dir = path.join(root, String(++count));
  fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, 'start.sh'), content);
  fs.writeFileSync(path.join(dir, 'server.js'), '// fixture');
  return dir;
}
function run(dir, ...args) {
  const result = spawnSync(process.execPath, [script, '--dir', dir, ...args], {encoding:'utf8'});
  if (result.error) throw result.error;
  return result;
}
function read(dir) { return fs.readFileSync(path.join(dir,'start.sh'), 'utf8'); }
const original = '#!/bin/bash\ncd "$(dirname "$0")"\nnode "server.js" "$@"\n';
const dir = fixture(original);
assert.equal(run(dir, '--size', '4096', '--dry-run').status, 0);
assert.equal(read(dir), original);
assert.equal(fs.readdirSync(dir).length, 2);
assert.equal(run(dir, '--size', '4096').status, 0);
assert.equal(read(dir), original.replace('node "server.js"', 'node --max-old-space-size=4096 "server.js"'));
const backup = fs.readdirSync(dir).find(n => n.startsWith('start.sh.memory-backup-'));
assert.equal(fs.readFileSync(path.join(dir, backup), 'utf8'), original);
assert.equal(run(dir, '--size', '4096').status, 0);
assert.equal(fs.readdirSync(dir).length, 3);
assert.equal(run(dir, '--restore', path.join(dir,backup), '--dry-run').status, 0);
assert.match(read(dir), /4096/);
assert.equal(run(dir, '--restore', path.join(dir,backup)).status, 0);
assert.equal(read(dir), original);
for (const text of [
  '#!/bin/bash\r\nexec node --max-old-space-size=8192 "server.js" "$@" # launch\r\n',
  "node --max_old_space_size=1024 './server.js' \"$@\"",
]) {
  const dir = fixture(text);
  assert.equal(run(dir, '--size','2048').status, 0);
  assert.equal(read(dir), text.replace(/--max[-_]old[-_]space[-_]size=\d+/, '--max-old-space-size=2048'));
}
for (const text of ['node --trace-warnings server.js "$@"\n', 'node server.js "$@"\nnode server.js "$@"\n', '# node server.js "$@"\n']) {
  const dir = fixture(text);
  assert.equal(run(dir, '--size','2048').status, 1);
  assert.equal(read(dir), text);
  assert.equal(fs.readdirSync(dir).length, 2);
}
for (const args of [['--size','0'],['--size','8192oops'],['--size','4096','--restore','x'],['--size','4096','--size','2048']]) {
  const dir = fixture(original);
  assert.equal(run(dir, ...args).status,1);
  assert.equal(read(dir),original);
}
console.log('PASS: preview, patch, backup, idempotence, restore, CRLF, existing flag, ambiguous/custom command rejection, invalid inputs');
