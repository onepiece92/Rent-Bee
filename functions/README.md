# Rent Bee functions: emailed sign-in codes

`requestEmailCode` emails a 6-digit code; `verifyEmailCode` checks it and
returns a custom token for the account that owns the email. Rules and limits
live in `codes.js` (tested by `npm test`).

## One-time setup

1. Create a Gmail app password for the mailbox that will send the codes
   (Google Account → Security → 2-Step Verification → App passwords).
2. Store both secrets:

       firebase functions:secrets:set SMTP_USER   # the Gmail address
       firebase functions:secrets:set SMTP_PASS   # the app password

3. Deploy:

       firebase deploy --only functions --project rent-bee-498712

The functions run in `asia-south1` as the Firebase Admin SDK service account,
which is allowed to sign the custom tokens.
