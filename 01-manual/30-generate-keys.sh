#!/usr/bin/env bash
set -euo pipefail

# Generates JWT_SECRET plus the matching ANON_KEY and SERVICE_ROLE_KEY.
#
# This is the thing people get wrong live. The anon and service_role keys are not
# random strings you can invent -- they are HS256 JWTs *signed with* JWT_SECRET.
# Rotate the secret without regenerating both keys and every request 401s while
# Studio itself still loads perfectly. That mismatch is demo trap #1.
#
# Usage:
#   ./30-generate-keys.sh              # fresh secret + matching keys
#   JWT_SECRET=... ./30-generate-keys.sh   # keys for an existing secret
#   ./30-generate-keys.sh --mismatch   # keys signed with the WRONG secret (trap #1)

MISMATCH=0
[[ "${1:-}" == "--mismatch" ]] && MISMATCH=1

JWT_SECRET="${JWT_SECRET:-$(openssl rand -hex 32)}"
SIGNING_SECRET="$JWT_SECRET"
if [[ $MISMATCH -eq 1 ]]; then
  # Sign with a different secret than the one we hand to the stack.
  SIGNING_SECRET="$(openssl rand -hex 32)"
fi

IAT=$(date +%s)
EXP=$(( IAT + 60*60*24*365*10 ))   # 10 years

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

sign() {
  local claims="$1" header payload sig
  header=$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | b64url)
  payload=$(printf '%s' "$claims" | b64url)
  sig=$(printf '%s' "${header}.${payload}" \
        | openssl dgst -sha256 -hmac "$SIGNING_SECRET" -binary | b64url)
  printf '%s.%s.%s' "$header" "$payload" "$sig"
}

ANON_KEY=$(sign "{\"role\":\"anon\",\"iss\":\"supabase\",\"iat\":${IAT},\"exp\":${EXP}}")
SERVICE_ROLE_KEY=$(sign "{\"role\":\"service_role\",\"iss\":\"supabase\",\"iat\":${IAT},\"exp\":${EXP}}")

cat <<OUT
JWT_SECRET=${JWT_SECRET}
ANON_KEY=${ANON_KEY}
SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY}
POSTGRES_PASSWORD=$(openssl rand -hex 24)
DASHBOARD_PASSWORD=$(openssl rand -hex 12)
SECRET_KEY_BASE=$(openssl rand -hex 32)
VAULT_ENC_KEY=$(openssl rand -hex 16)
OUT

if [[ $MISMATCH -eq 1 ]]; then
  echo "" >&2
  echo ">>> TRAP MODE: these keys are signed with a DIFFERENT secret." >&2
  echo ">>> Studio will load. Every API call will 401. That is the lesson." >&2
fi
