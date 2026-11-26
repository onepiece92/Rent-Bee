const test = require('node:test');
const assert = require('node:assert/strict');
const c = require('./codes');

const T0 = 1_800_000_000_000;

test('emails are normalized and validated', () => {
  assert.equal(c.normalizeEmail('  Owner@Gmail.COM '), 'owner@gmail.com');
  assert.equal(c.normalizeEmail(42), '');
  assert.ok(c.isValidEmail('owner@gmail.com'));
  for (const bad of ['', 'owner', 'owner@', '@gmail.com', 'a b@gmail.com', 'owner@gmail', 'a@b@c.com']) {
    assert.ok(!c.isValidEmail(bad), bad);
  }
});

test('codes are six digits and the key hides the address', () => {
  for (let i = 0; i < 200; i++) assert.match(c.newCode(), /^\d{6}$/);
  assert.match(c.emailKey('owner@gmail.com'), /^[0-9a-f]{64}$/);
});

test('a code checks out only when right, fresh and not over the attempt limit', () => {
  const doc = { hash: c.hashCode('123456', 's'), salt: 's', expiresAt: T0 + c.CODE_TTL_MS, attempts: 0 };
  assert.equal(c.checkCode(doc, '123456', T0), 'ok');
  assert.equal(c.checkCode(doc, '654321', T0), 'wrong');
  assert.equal(c.checkCode(doc, '123456', T0 + c.CODE_TTL_MS + 1), 'expired');
  assert.equal(c.checkCode({ ...doc, attempts: c.MAX_ATTEMPTS }, '123456', T0), 'locked');
  assert.equal(c.checkCode(undefined, '123456', T0), 'none');
  assert.equal(c.checkCode({ ...doc, hash: null }, '123456', T0), 'none', 'a used code is gone');
});

test('sends are spaced a minute apart and capped per hour', () => {
  let s = c.checkSend(undefined, T0);
  assert.deepEqual(s, { ok: true, sendCount: 1, windowStart: T0 });
  const doc = { sentAt: T0, sendCount: 1, windowStart: T0 };
  assert.equal(c.checkSend(doc, T0 + 30_000).reason, 'wait');
  assert.equal(c.checkSend(doc, T0 + 61_000).sendCount, 2);
  const full = { sentAt: T0, sendCount: c.SENDS_PER_HOUR, windowStart: T0 };
  assert.equal(c.checkSend(full, T0 + 10 * 60_000).reason, 'hourly');
  s = c.checkSend(full, T0 + 61 * 60_000);
  assert.deepEqual(s, { ok: true, sendCount: 1, windowStart: T0 + 61 * 60_000 });
});

test('the project-wide daily cap resets after a day', () => {
  const full = { count: c.GLOBAL_SENDS_PER_DAY, windowStart: T0 };
  assert.equal(c.checkGlobal(full, T0 + 1000).ok, false);
  assert.deepEqual(c.checkGlobal(full, T0 + 25 * 3600_000), { ok: true, count: 1, windowStart: T0 + 25 * 3600_000 });
  assert.equal(c.checkGlobal(undefined, T0).count, 1);
});
