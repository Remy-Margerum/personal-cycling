#!/bin/bash
# Checks the TestFlight signing secrets before anything slow runs, and
# decodes the certificate and provisioning profile into the given folder:
#   certificate.p12, profile.mobileprovision
# Reads the secrets from the environment. Prints only facts about them
# (lengths, formats, which one is wrong), never their values.
# Tested on Linux by .github/scripts/test-check-signing-secrets.sh.
set -uo pipefail

out=${1:?usage: check-signing-secrets.sh <output folder>}
openssl=${OPENSSL:-openssl}
problems=0

fail() {
  echo "::error::$1"
  problems=$((problems + 1))
}

# Base64 secret -> file. Spaces and line breaks (including Windows CRLF
# from copy-paste) are dropped first; anything else outside the base64
# alphabet means the wrong thing was pasted.
decode() {
  local name=$1 file=$2
  local cleaned bad
  cleaned=$(printf '%s' "${!name}" | tr -d ' \t\r\n')
  if [ -z "$cleaned" ]; then
    fail "$name is empty."
    return 1
  fi
  bad=$(printf '%s' "$cleaned" | tr -d 'A-Za-z0-9+/=' | wc -c | tr -d ' ')
  if [ "$bad" -ne 0 ]; then
    fail "$name isn't base64: $bad of its ${#cleaned} characters can't appear in base64, so something other than the base64 output was pasted. Copy it again with the command in PLAN.md (Phase 3, step 6)."
    return 1
  fi
  if ! printf '%s' "$cleaned" | base64 --decode > "$file" 2> /dev/null; then
    fail "$name looks like base64 but doesn't decode (${#cleaned} characters, so it may be cut off). Copy it again with the command in PLAN.md (Phase 3, step 6)."
    return 1
  fi
  echo "$name: OK, decodes to $(wc -c < "$file" | tr -d ' ') bytes"
}

# Short identifiers: exact shape, no spaces or line breaks around them.
check_id() {
  local name=$1 pattern=$2 description=$3
  local value=${!name}
  if [[ $value =~ $pattern ]]; then
    echo "$name: OK"
  else
    fail "$name should be $description, but it's ${#value} characters long or contains other characters (a space or line break pasted with it?)."
  fi
}

mkdir -p "$out"

check_id APPLE_TEAM_ID '^[A-Z0-9]{10}$' "10 capital letters and digits (developer.apple.com → Membership details)"
check_id ASC_KEY_ID '^[A-Z0-9]{10}$' "10 capital letters and digits (the Key ID in the API key's row)"
check_id ASC_ISSUER_ID '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' \
  "a UUID like 69a6de7e-…-…-…-… (the Issuer ID above the API key list)"

if [[ $ASC_KEY_P8 != *"-----BEGIN PRIVATE KEY-----"* || $ASC_KEY_P8 != *"-----END PRIVATE KEY-----"* ]]; then
  fail "ASC_KEY_P8 should be the whole AuthKey_….p8 file, including the -----BEGIN PRIVATE KEY----- and -----END PRIVATE KEY----- lines."
elif ! printf '%s\n' "$ASC_KEY_P8" | tr -d '\r' | "$openssl" pkey -noout 2> /dev/null; then
  fail "ASC_KEY_P8 has the BEGIN/END lines but isn't a readable private key (cut off or edited?). Paste the whole .p8 file again."
else
  echo "ASC_KEY_P8: OK"
fi

if decode BUILD_CERTIFICATE_BASE64 "$out/certificate.p12"; then
  if ! "$openssl" pkcs12 -in "$out/certificate.p12" -noout -passin env:P12_PASSWORD 2> /dev/null; then
    fail "The certificate (.p12) doesn't open with P12_PASSWORD. Either the password secret is wrong, or the .p12 was made without the -certpbe/-keypbe/-macalg flags. Fix whichever it is and update the secret."
  else
    echo "P12_PASSWORD: OK, opens the .p12"
    subject=$("$openssl" pkcs12 -in "$out/certificate.p12" -nokeys -passin env:P12_PASSWORD 2> /dev/null \
      | "$openssl" x509 -noout -subject 2> /dev/null)
    if [[ $subject != *"Apple Distribution"* ]]; then
      fail "The .p12's certificate isn't an Apple Distribution certificate. Make the certificate under Certificates → Apple Distribution."
    elif [[ $subject != *"$APPLE_TEAM_ID"* ]]; then
      fail "The .p12's certificate belongs to a different team than APPLE_TEAM_ID."
    else
      echo "Certificate: OK, Apple Distribution for this team"
    fi
  fi
fi

decode PROVISIONING_PROFILE_BASE64 "$out/profile.mobileprovision" || true

if [ "$problems" -gt 0 ]; then
  echo "$problems problem(s) with the signing secrets; see the errors above."
  exit 1
fi
echo "All signing secrets look right."
