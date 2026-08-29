#!/usr/bin/env bash
# Step 50 -- pull images and start the stack, then wait until it actually answers.
#
# The pull is 4-5 minutes and it is the longest silence in the demo. Run this,
# then go to your architecture diagram; come back when it says READY.
set -euo pipefail
say(){ printf '\033[1m==>\033[0m %s\n' "$*"; }

INSTALL_DIR="${INSTALL_DIR:-/opt/supabase}"
cd "${INSTALL_DIR}/supabase/docker" 2>/dev/null || {
  echo "stack not found -- run ./20-fetch-supabase.sh first" >&2; exit 1; }

grep -q '^ANON_KEY=eyJ' .env || {
  echo "ANON_KEY doesn't look like a JWT -- run ./40-configure-env.sh first" >&2; exit 1; }

say "Pulling images (4-5 min -- this is your diagram slot)"
docker compose pull --quiet

say "Starting"
docker compose up -d

say "Waiting for Kong to answer on :8000"
for i in $(seq 1 60); do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://localhost:8000/ 2>/dev/null || echo 000)
  # Kong answers 401/404 before Studio is fully warm; anything non-000 means it's up.
  if [[ "$CODE" != "000" ]]; then
    echo ""
    say "READY -- Kong responding (HTTP ${CODE})"
    HOST=$(grep '^SUPABASE_PUBLIC_URL=' .env | cut -d= -f2-)
    echo "    Studio: ${HOST}"
    echo "    Login : $(grep '^DASHBOARD_USERNAME=' .env | cut -d= -f2-) / $(grep '^DASHBOARD_PASSWORD=' .env | cut -d= -f2-)"
    exit 0
  fi
  printf '.'; sleep 5
done

echo ""
say "Kong never answered. Container status:"
docker compose ps
echo ""
echo "    Most likely: OOM (check 'docker compose logs db'), or analytics"
echo "    crash-looping because you are not on the pinned SHA."
exit 1
