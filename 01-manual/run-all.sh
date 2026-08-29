#!/usr/bin/env bash
# Rehearsal only -- runs every step end to end.
# Do NOT use this live: the whole point is running the steps one at a time so the
# audience sees each piece, and so a failure costs you one step, not all of them.
set -euo pipefail
PUBLIC_IP="${1:?usage: sudo ./run-all.sh <PUBLIC_IP>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/opt/supabase}"

"$HERE/00-preflight.sh"
"$HERE/10-install-docker.sh"
"$HERE/20-fetch-supabase.sh"
( cd "${INSTALL_DIR}/supabase/docker" && "$HERE/40-configure-env.sh" "$PUBLIC_IP" )
"$HERE/50-up.sh"
