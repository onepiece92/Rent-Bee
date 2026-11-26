// Emailed sign-in codes for Rent Bee.
//
//   requestEmailCode({email})        emails a 6-digit code
//   verifyEmailCode({email, code})   checks it and returns a custom token for
//                                    the account that owns the address
//
// One account per email: an existing account with that email (including a
// phone account the address was attached to) is reused, otherwise one is
// created. Codes are stored hashed under emailCodes/{sha256(email)}, which no
// client can read (firestore.rules denies everything it does not list).
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const codes = require('./codes');

admin.initializeApp();

// The mailbox the codes are sent from: a Gmail address and an app password
// for it (Google Account → Security → App passwords).
const SMTP_USER = defineSecret('SMTP_USER');
const SMTP_PASS = defineSecret('SMTP_PASS');

const options = {
  region: 'asia-south1',
  // Signing custom tokens needs a service account that may sign as itself;
  // the Firebase Admin SDK account can.
  serviceAccount: 'firebase-adminsdk-fbsvc@rent-bee-498712.iam.gserviceaccount.com',
  maxInstances: 5,
};

const db = () => admin.firestore();
const codeRef = (email) => db().collection('emailCodes').doc(codes.emailKey(email));
const globalRef = () => db().collection('emailCodes').doc('_global');

function readEmail(data) {
  const email = codes.normalizeEmail(data && data.email);
  if (!codes.isValidEmail(email)) {
    throw new HttpsError('invalid-argument', 'Enter a valid email address.');
  }
  return email;
}

exports.requestEmailCode = onCall(
  { ...options, secrets: [SMTP_USER, SMTP_PASS] },
  async (request) => {
    const email = readEmail(request.data);
    const code = codes.newCode();
    const salt = codes.newSalt();
    const now = Date.now();

    // Reserve the send (per-address and project-wide limits) before mailing.
    await db().runTransaction(async (tx) => {
      const [own, global] = await Promise.all([tx.get(codeRef(email)), tx.get(globalRef())]);
      const send = codes.checkSend(own.data(), now);
      if (!send.ok) {
        throw new HttpsError(
          'resource-exhausted',
          send.reason === 'wait'
            ? 'A code was just sent. Wait a minute before asking for another.'
            : 'Too many codes requested for this email. Try again in an hour.',
        );
      }
      const all = codes.checkGlobal(global.data(), now);
      if (!all.ok) {
        throw new HttpsError('resource-exhausted', 'Email sign-in is busy. Try again later.');
      }
      tx.set(codeRef(email), {
        hash: codes.hashCode(code, salt),
        salt,
        expiresAt: now + codes.CODE_TTL_MS,
        attempts: 0,
        sentAt: now,
        sendCount: send.sendCount,
        windowStart: send.windowStart,
      });
      tx.set(globalRef(), { count: all.count, windowStart: all.windowStart });
    });

    const transport = nodemailer.createTransport({
      host: 'smtp.gmail.com',
      port: 465,
      secure: true,
      auth: { user: SMTP_USER.value(), pass: SMTP_PASS.value() },
    });
    try {
      await transport.sendMail({
        from: `"Rent Bee" <${SMTP_USER.value()}>`,
        to: email,
        subject: `${code} is your Rent Bee sign-in code`,
        text:
          `Your Rent Bee sign-in code is ${code}\n\n` +
          'It works for 10 minutes. If you did not ask for it, you can ignore this email.',
      });
    } catch (e) {
      console.error('requestEmailCode: send failed', e);
      throw new HttpsError('deadline-exceeded', 'Could not send the email. Try again shortly.');
    }
    return { ok: true };
  },
);

exports.verifyEmailCode = onCall(options, async (request) => {
  const email = readEmail(request.data);
  const code = String((request.data && request.data.code) || '').trim();
  if (!/^\d{6}$/.test(code)) {
    throw new HttpsError('invalid-argument', 'Enter the 6-digit code.');
  }
  const now = Date.now();

  // Judge and consume in one transaction: a correct code is single-use, a
  // wrong one counts against the attempt limit.
  const verdict = await db().runTransaction(async (tx) => {
    const snap = await tx.get(codeRef(email));
    const doc = snap.data();
    const result = codes.checkCode(doc, code, now);
    if (result === 'ok') {
      // Keep the send counters so the hourly limit still applies.
      tx.update(codeRef(email), { hash: null, salt: null });
    } else if (result === 'wrong') {
      tx.update(codeRef(email), { attempts: doc.attempts + 1 });
    }
    return result;
  });

  if (verdict === 'wrong') {
    throw new HttpsError('permission-denied', 'Incorrect code. Check the email and try again.');
  }
  if (verdict !== 'ok') {
    throw new HttpsError(
      'failed-precondition',
      verdict === 'locked'
        ? 'Too many wrong tries. Ask for a new code.'
        : 'That code has expired. Ask for a new one.',
    );
  }

  let user;
  try {
    user = await admin.auth().getUserByEmail(email);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    user = await admin.auth().createUser({ email, emailVerified: true });
  }
  if (user.disabled) {
    throw new HttpsError('permission-denied', 'This account has been disabled.');
  }
  if (!user.emailVerified) {
    await admin.auth().updateUser(user.uid, { emailVerified: true });
  }
  return { token: await admin.auth().createCustomToken(user.uid) };
});
