#!/usr/bin/env python3
"""Attach an email address to an existing phone sign-in account.

After this, signing in with that email (Google, or the emailed code) opens the
same account — and so the same ledger — as the phone number did.

    python tool/attach_email_to_account.py +9779800000000 owner@example.com

Needs google-auth and requests, and the Firebase Admin SDK key file named in
RENTBEE_SA (default: the one in ~/Downloads). Refuses to act when the email
already belongs to a different account. Prints what it changed.
"""
import glob
import os
import sys

from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

PROJECT = "rent-bee-498712"
API = f"https://identitytoolkit.googleapis.com/v1/projects/{PROJECT}"


def main() -> int:
    if len(sys.argv) != 3 or not sys.argv[1].startswith("+") or "@" not in sys.argv[2]:
        print(__doc__)
        return 2
    phone, email = sys.argv[1], sys.argv[2].strip().lower()
    key = os.environ.get("RENTBEE_SA") or next(
        iter(glob.glob(os.path.expanduser(f"~/Downloads/{PROJECT}-firebase-adminsdk-*.json"))), None)
    if not key:
        print("No Admin SDK key file found; set RENTBEE_SA to its path.")
        return 1
    creds = service_account.Credentials.from_service_account_file(
        key, scopes=["https://www.googleapis.com/auth/cloud-platform"])
    s = AuthorizedSession(creds)

    def lookup(field, value):
        r = s.post(f"{API}/accounts:lookup", json={field: [value]})
        r.raise_for_status()
        return r.json().get("users", [])

    by_phone = lookup("phoneNumber", phone)
    if not by_phone:
        print(f"No account signs in with {phone}.")
        return 1
    user = by_phone[0]
    uid = user["localId"]
    by_email = lookup("email", email)
    if by_email and by_email[0]["localId"] != uid:
        print(f"{email} already belongs to a different account ({by_email[0]['localId']}). "
              "Nothing changed. Delete that account first if it is empty.")
        return 1
    if user.get("email") and user["email"].lower() != email:
        print(f"This account already has the email {user['email']}. Nothing changed.")
        return 1
    r = s.post(f"{API}/accounts:update",
               json={"localId": uid, "email": email, "emailVerified": True})
    r.raise_for_status()
    print(f"Done: {email} now signs in to the account of {phone} (uid {uid}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
