#!/usr/bin/env bash
# Step 20 -- fetch the Supabase self-host stack at a PINNED commit.
#
# Pin it. Upstream's docker-compose.yml and .env.example change shape between
# releases; rehearsing on main and presenting a week later on a different main is
# how live demos get ambushed. Find a SHA, rehearse on it, present on it:
#     git ls-remote https://github.com/supabase/supabase.git HEAD
set -euo pipefail
say(){ printf '\033[1m==>\033[0m %s\n' "$*"; }

SUPABASE_COMMIT="${SUPABASE_COMMIT:-HEAD}"
INSTALL_DIR="${INSTALL_DIR:-/opt/supabase}"
REPO="${INSTALL_DIR}/supabase"

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
command -v git >/dev/null || { echo "git missing -- run ./10-install-docker.sh first" >&2; exit 1; }

[[ "$SUPABASE_COMMIT" == "HEAD" ]] && \
  printf '    \033[33mWARN\033[0m tracking HEAD. Pin a SHA before going live.\n'

mkdir -p "$INSTALL_DIR"
if [[ ! -d "${REPO}/.git" ]]; then
  say "Cloning supabase/supabase (blobless + sparse -- we only need docker/)"
  git clone --filter=blob:none --no-checkout \
      https://github.com/supabase/supabase.git "$REPO"
  git -C "$REPO" sparse-checkout set --cone docker
else
  say "Repo already present -- fetching"
fi

# Fetch by ref OR by SHA. HEAD works whatever upstream calls its default branch
# -- supabase/supabase uses master, not main, which is exactly the kind of thing
# you do not want to discover live.
say "Checking out ${SUPABASE_COMMIT}"
if ! git -C "$REPO" fetch --depth 1 origin "$SUPABASE_COMMIT" 2>/dev/null; then
  echo "" >&2
  echo "Could not fetch ref '${SUPABASE_COMMIT}'." >&2
  echo "Upstream's default branch is: $(git ls-remote --symref https://github.com/supabase/supabase.git HEAD 2>/dev/null | awk '/^ref:/{sub(/refs\/heads\//,"",$2); print $2}')" >&2
  echo "Use SUPABASE_COMMIT=HEAD, or pin a SHA from:" >&2
  echo "  git ls-remote https://github.com/supabase/supabase.git HEAD" >&2
  exit 1
fi
git -C "$REPO" checkout --detach FETCH_HEAD

[[ -d "${REPO}/docker" ]] || { echo "sparse checkout has no docker/ -- wrong ref?" >&2; exit 1; }

cd "${REPO}/docker"
if [[ -f .env ]]; then
  say ".env already exists -- leaving it alone"
else
  cp .env.example .env
  say "Created .env from .env.example (all placeholder values)"
fi

echo ""
say "Pinned at $(git -C "$REPO" rev-parse --short HEAD)"
echo "    $(ls -1 | tr '\n' ' ')"
echo ""
say "Next: cd ${REPO}/docker && sudo <path>/40-configure-env.sh <PUBLIC_IP>"
