#!/bin/bash
# Tests check-signing-secrets.sh with throwaway keys made here (no real
# secrets). Runs on the macOS CI runner, where the real check runs, and on
# Linux: bash .github/scripts/test-check-signing-secrets.sh
set -euo pipefail

b64() { base64 < "$1" | tr -d '\n'; }        # one line, GNU and BSD alike
crlf() { awk '{ printf "%s\r\n", $0 }'; }    # Windows line endings

script="$(cd "$(dirname "$0")" && pwd)/check-signing-secrets.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

# A self-signed stand-in for the Apple Distribution certificate, packed the
# way PLAN.md says (3DES + SHA-1 MAC, readable by macOS).
team=ABCDE12345
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 2 \
  -subj "/UID=XYZ/CN=Apple Distribution: Test Rider ($team)/OU=$team/O=Test Rider/C=US" 2> /dev/null
openssl pkcs12 -export -inkey key.pem -in cert.pem -out good.p12 -passout pass:right-password \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 2> /dev/null \
  || openssl pkcs12 -export -inkey key.pem -in cert.pem -out good.p12 -passout pass:right-password
openssl ecparam -name prime256v1 -genkey -noout 2> /dev/null | openssl pkcs8 -topk8 -nocrypt > AuthKey.p8
head -c 3000 /dev/urandom > profile.mobileprovision

good_env() {
  export APPLE_TEAM_ID=$team
  export ASC_KEY_ID=K1234567AB
  export ASC_ISSUER_ID=69a6de7e-1234-47e3-e053-5b8c7c11a4d1
  export ASC_KEY_P8="$(cat AuthKey.p8)"
  export P12_PASSWORD=right-password
  export BUILD_CERTIFICATE_BASE64="$(b64 good.p12)"
  export PROVISIONING_PROFILE_BASE64="$(b64 profile.mobileprovision)"
}

failures=0
# expect <pass|fail> <description> [text the output must contain]
expect() {
  local want=$1 what=$2 needle=${3:-}
  local output status
  output=$("$script" out 2>&1) && status=pass || status=fail
  if [ "$status" != "$want" ] || [[ -n $needle && $output != *"$needle"* ]]; then
    echo "FAIL: $what (expected $want${needle:+ with \"$needle\"}, got $status)"
    echo "$output" | sed 's/^/    /'
    failures=$((failures + 1))
  else
    echo "ok: $what"
  fi
  if [[ $output == *"right-password"* || $output == *"${BUILD_CERTIFICATE_BASE64:0:40}"* ]]; then
    echo "FAIL: $what printed a secret value"
    failures=$((failures + 1))
  fi
}

good_env
expect pass "all secrets right" "All signing secrets look right"
cmp -s out/certificate.p12 good.p12 && echo "ok: certificate decoded byte for byte" \
  || { echo "FAIL: decoded certificate differs"; failures=$((failures + 1)); }
cmp -s out/profile.mobileprovision profile.mobileprovision && echo "ok: profile decoded byte for byte" \
  || { echo "FAIL: decoded profile differs"; failures=$((failures + 1)); }

good_env; BUILD_CERTIFICATE_BASE64="$(b64 good.p12 | fold -w 76 | crlf)"   # wrapped, CRLF
expect pass "base64 with Windows line breaks is accepted" "All signing secrets look right"

good_env; ASC_KEY_P8="$(crlf < AuthKey.p8)"
expect pass "p8 with Windows line breaks is accepted" "ASC_KEY_P8: OK"

good_env; BUILD_CERTIFICATE_BASE64='base64 -w 0 ~/BikeComputerSigning/distribution.p12 | clip'
expect fail "command pasted instead of its output" "BUILD_CERTIFICATE_BASE64 isn't base64"

good_env; PROVISIONING_PROFILE_BASE64="${PROVISIONING_PROFILE_BASE64:0:1001}"
expect fail "cut-off profile" "PROVISIONING_PROFILE_BASE64 looks like base64 but doesn't decode"

good_env; PROVISIONING_PROFILE_BASE64=""
expect fail "empty profile" "PROVISIONING_PROFILE_BASE64 is empty"

good_env; P12_PASSWORD=wrong-password
expect fail "wrong .p12 password" "doesn't open with P12_PASSWORD"

good_env; APPLE_TEAM_ID="ZZZZZ99999"
expect fail "certificate from another team" "different team than APPLE_TEAM_ID"

good_env; APPLE_TEAM_ID="$team "
expect fail "team ID with a trailing space" "APPLE_TEAM_ID should be"

good_env; ASC_ISSUER_ID="not-a-uuid"
expect fail "bad issuer ID" "ASC_ISSUER_ID should be"

good_env; ASC_KEY_P8="$(grep -v PRIVATE AuthKey.p8)"
expect fail "p8 without BEGIN/END lines" "including the -----BEGIN PRIVATE KEY-----"

good_env; ASC_KEY_P8="$(head -2 AuthKey.p8; echo '-----END PRIVATE KEY-----')"
expect fail "cut-off p8" "isn't a readable private key"

if [ "$failures" -gt 0 ]; then
  echo "$failures check(s) failed"
  exit 1
fi
echo "all checks passed"
