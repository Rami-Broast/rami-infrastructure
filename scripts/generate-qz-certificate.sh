#!/usr/bin/env bash
#
# Generate the self-signed pair that stops QZ Tray asking every counter to
# allow printing.
#
# Run this ONCE, on a machine you trust — not on a branch terminal. It writes
# two files into the current directory:
#
#   qz-certificate.pem   the certificate. PUBLIC. It is served to every branch
#                        by the API and embedded in the installer the POS hands
#                        out, so it is not a secret and does not need guarding.
#
#   qz-private-key.pem   the private key. A SECRET, in the same class as the
#                        database password. It goes into Secret Manager as
#                        QZ_SIGNING_PRIVATE_KEY and nowhere else — never a
#                        repository, never a chat message, never a branch
#                        machine. Delete the local copy once it is stored.
#
# Both go to the backend together: it refuses to boot on half a pair, because a
# certificate with no key signs nothing while the person who set it believes
# printing is configured.
#
# The branches need nothing from this script. The POS builds their installer
# from the certificate the API serves.

set -euo pipefail

OUT_DIR="${1:-.}"
CERT="$OUT_DIR/qz-certificate.pem"
KEY="$OUT_DIR/qz-private-key.pem"

# Ten years: this certificate is trusted by a file on each counter machine, and
# an expiry is a day every branch stops printing at once, for a reason nobody
# on site can diagnose. Rotating it deliberately is a better failure than
# discovering it on a Friday.
DAYS="${DAYS:-3650}"
SUBJECT="${SUBJECT:-/CN=Rami Broast/O=Rami Broast/C=SA}"

if [ -e "$CERT" ] || [ -e "$KEY" ]; then
  echo "Refusing to overwrite existing files in $OUT_DIR." >&2
  echo "A replaced key means every counter machine needs the new certificate installed again." >&2
  exit 1
fi

command -v openssl >/dev/null 2>&1 || { echo "openssl is required." >&2; exit 1; }

umask 077
openssl req -x509 -newkey rsa:2048 -sha512 \
  -keyout "$KEY" -out "$CERT" \
  -days "$DAYS" -nodes -subj "$SUBJECT"

chmod 600 "$KEY"
chmod 644 "$CERT"

cat <<SUMMARY

Done.

  $CERT   → QZ_SIGNING_CERTIFICATE   (public)
  $KEY   → QZ_SIGNING_PRIVATE_KEY   (SECRET)

Next:

  1. Put both into Secret Manager, together:
       scripts/setup-secrets.sh   (see docs/secrets.md)
  2. Redeploy the backend so it picks them up.
  3. At each branch: Branch POS → Print settings → "Download the certificate
     installer", then run that one file as administrator. Nothing to email,
     no path to type.

  Then delete your local copy of $KEY.

SUMMARY
