#!/usr/bin/env bash
set -euo pipefail

# Patches Supabase's stock docker/.env in place, by key.
#
# We deliberately do NOT ship a full .env file: upstream's .env.example changes
# shape between releases (the analytics/Logflare vars have been renamed more than
# once). Patching by key means this keeps working when you bump the pinned commit.
#
# Usage:
#   ./40-configure-env.sh <public-host>              # working config
#   ./40-configure-env.sh <public-host> --break localhost
#   ./40-configure-env.sh <public-host> --break jwt
#
#   <public-host> is the address the BROWSER will use: an EC2 public IP or domain.

ENV_FILE="${ENV_FILE:-./.env}"
PUBLIC_HOST="${1:?usage: 40-configure-env.sh <public-host|EIP> [--break localhost|jwt]}"
BREAK=""
[[ "${2:-}" == "--break" ]] && BREAK="${3:?--break needs: localhost or jwt}"

[[ -f "$ENV_FILE" ]] || { echo "no $ENV_FILE -- run 'cp .env.example .env' first" >&2; exit 1; }

# Set KEY=VALUE: replace the line if the key exists, append if it doesn't.
set_env() {
  local key="$1" val="$2"
  if grep -qE "^${key}=" "$ENV_FILE"; then
    # Use a non-/ delimiter; values contain URLs and base64.
    sed -i.bak -E "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$val" >> "$ENV_FILE"
  fi
}

KEYGEN_ARGS=()
[[ "$BREAK" == "jwt" ]] && KEYGEN_ARGS+=(--mismatch)
eval "$("$(dirname "$0")/30-generate-keys.sh" "${KEYGEN_ARGS[@]}" | sed 's/^/export /')"

set_env POSTGRES_PASSWORD   "$POSTGRES_PASSWORD"
set_env JWT_SECRET          "$JWT_SECRET"
set_env ANON_KEY            "$ANON_KEY"
set_env SERVICE_ROLE_KEY    "$SERVICE_ROLE_KEY"
set_env SECRET_KEY_BASE     "$SECRET_KEY_BASE"
set_env VAULT_ENC_KEY       "$VAULT_ENC_KEY"
set_env DASHBOARD_USERNAME  "supabase"
set_env DASHBOARD_PASSWORD  "$DASHBOARD_PASSWORD"

if [[ "$BREAK" == "localhost" ]]; then
  # Trap #2: Studio renders fine, then every request fails, because the BROWSER
  # resolves localhost to the viewer's own machine -- not to the EC2 box.
  set_env SITE_URL            "http://localhost:3000"
  set_env API_EXTERNAL_URL    "http://localhost:8000"
  set_env SUPABASE_PUBLIC_URL "http://localhost:8000"
else
  set_env SITE_URL            "http://${PUBLIC_HOST}:8000"
  set_env API_EXTERNAL_URL    "http://${PUBLIC_HOST}:8000"
  set_env SUPABASE_PUBLIC_URL "http://${PUBLIC_HOST}:8000"
fi

rm -f "${ENV_FILE}.bak"

echo "Patched ${ENV_FILE}"
echo "  Studio    : http://${PUBLIC_HOST}:8000"
echo "  user/pass : supabase / ${DASHBOARD_PASSWORD}"
case "$BREAK" in
  jwt)       echo "  MODE      : BROKEN (jwt mismatch) -- Studio loads, API 401s" ;;
  localhost) echo "  MODE      : BROKEN (localhost URLs) -- Studio loads, API unreachable" ;;
  *)         echo "  MODE      : working" ;;
esac
