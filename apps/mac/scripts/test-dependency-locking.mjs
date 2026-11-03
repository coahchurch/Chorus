import assert from 'node:assert/strict';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const macDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'mxu-dependency-lock-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(join(root, 'scripts'));
  cpSync(join(macDir, 'scripts/prepare-dependencies.mjs'), join(root, 'scripts/prepare-dependencies.mjs'));
  for (const name of ['LocalAPI', 'StreamEngine']) {
    mkdirSync(join(root, 'Packages', name), { recursive: true });
    cpSync(join(macDir, 'Packages', name, 'Package.resolved'), join(root, 'Packages', name, 'Package.resolved'));
  }
  return {
    root,
    lock: join(root, 'Chorus.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'),
    run: (...args) => spawnSync(process.execPath, [join(root, 'scripts/prepare-dependencies.mjs'), ...args], { encoding: 'utf8' }),
  };
}

test('pins app dependencies from the committed package locks', t => {
  const f = fixture(t);
  assert.equal(f.run().status, 0);
  assert.equal(f.run('--check').status, 0);
  const pins = JSON.parse(readFileSync(f.lock)).pins;
  assert.deepEqual(pins.map(p => p.identity), ['flyingfox', 'haishinkit.swift', 'logboard']);
});

test('rejects missing or changed app pins', t => {
  const f = fixture(t);
  assert.equal(f.run().status, 0);
  const actual = JSON.parse(readFileSync(f.lock));
  actual.pins.pop();
  writeFileSync(f.lock, JSON.stringify(actual));
  assert.notEqual(f.run('--check').status, 0);
  assert.equal(f.run().status, 0);
  const changed = JSON.parse(readFileSync(f.lock));
  changed.pins[0].state.revision = '0'.repeat(40);
  writeFileSync(f.lock, JSON.stringify(changed));
  assert.notEqual(f.run('--check').status, 0);
});

test('rejects missing transitive pins in a package lock', t => {
  const f = fixture(t);
  const path = join(f.root, 'Packages/StreamEngine/Package.resolved');
  const lock = JSON.parse(readFileSync(path));
  lock.pins = lock.pins.filter(p => p.identity !== 'logboard');
  writeFileSync(path, JSON.stringify(lock));
  const result = f.run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Missing logboard dependency pin/);
});

test('rejects conflicting versions across package locks', t => {
  const f = fixture(t);
  const path = join(f.root, 'Packages/StreamEngine/Package.resolved');
  const lock = JSON.parse(readFileSync(path));
  const flyingFox = JSON.parse(readFileSync(join(f.root, 'Packages/LocalAPI/Package.resolved'))).pins[0];
  flyingFox.state.revision = '0'.repeat(40);
  lock.pins.push(flyingFox);
  writeFileSync(path, JSON.stringify(lock));
  const result = f.run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Conflicting dependency pins/);
});
