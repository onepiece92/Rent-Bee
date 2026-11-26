// Pure rules for the emailed sign-in code: no Firebase, no clock of its own,
// so they can be tested directly (see codes.test.js).
const crypto = require('node:crypto');

const CODE_TTL_MS = 10 * 60 * 1000; // a code works for 10 minutes
const RESEND_GAP_MS = 60 * 1000; // at most one email a minute per address
const SENDS_PER_HOUR = 5; // per address
const MAX_ATTEMPTS = 5; // wrong guesses before the code is dead
const GLOBAL_SENDS_PER_DAY = 300; // across all addresses

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

function normalizeEmail(raw) {
  return typeof raw === 'string' ? raw.trim().toLowerCase() : '';
}

function isValidEmail(email) {
  return email.length <= 254 && /^[^@\s]+@[^@\s]+\.[^@\s.]+$/.test(email);
}

// Firestore document id for an address: never the address itself.
function emailKey(email) {
  return crypto.createHash('sha256').update(email).digest('hex');
}

function newCode() {
  return String(crypto.randomInt(0, 1000000)).padStart(6, '0');
}

function hashCode(code, salt) {
  return crypto.createHash('sha256').update(`${salt}:${code}`).digest('hex');
}

function newSalt() {
  return crypto.randomBytes(16).toString('hex');
}

// Whether another code may be emailed to an address whose record is `doc`
// (undefined when there is none). Returns {ok, reason?, sendCount, windowStart}.
function checkSend(doc, now) {
  const inWindow = doc && now - doc.windowStart < HOUR_MS;
  const sendCount = inWindow ? doc.sendCount : 0;
  const windowStart = inWindow ? doc.windowStart : now;
  if (doc && now - doc.sentAt < RESEND_GAP_MS) {
    return { ok: false, reason: 'wait', sendCount, windowStart };
  }
  if (sendCount >= SENDS_PER_HOUR) {
    return { ok: false, reason: 'hourly', sendCount, windowStart };
  }
  return { ok: true, sendCount: sendCount + 1, windowStart };
}

// Same shape of check for the project-wide daily cap.
function checkGlobal(doc, now) {
  const inWindow = doc && now - doc.windowStart < DAY_MS;
  const count = inWindow ? doc.count : 0;
  const windowStart = inWindow ? doc.windowStart : now;
  if (count >= GLOBAL_SENDS_PER_DAY) return { ok: false, count, windowStart };
  return { ok: true, count: count + 1, windowStart };
}

// Judges a typed code against the stored record:
// 'ok' | 'none' | 'expired' | 'locked' | 'wrong'.
function checkCode(doc, code, now) {
  if (!doc || !doc.hash) return 'none';
  if (now > doc.expiresAt) return 'expired';
  if (doc.attempts >= MAX_ATTEMPTS) return 'locked';
  const given = Buffer.from(hashCode(String(code), doc.salt), 'hex');
  const want = Buffer.from(doc.hash, 'hex');
  const match = given.length === want.length && crypto.timingSafeEqual(given, want);
  return match ? 'ok' : 'wrong';
}

module.exports = {
  CODE_TTL_MS,
  MAX_ATTEMPTS,
  SENDS_PER_HOUR,
  GLOBAL_SENDS_PER_DAY,
  normalizeEmail,
  isValidEmail,
  emailKey,
  newCode,
  newSalt,
  hashCode,
  checkSend,
  checkGlobal,
  checkCode,
};
