#!/usr/bin/env bash
# Step 10 -- install Docker Engine + the compose plugin (Ubuntu).
# Idempotent: safe to re-run, skips straight to verification if already present.
set -euo pipefail
say(){ printf '\033[1m==>\033[0m %s\n' "$*"; }
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

if docker compose version >/dev/null 2>&1; then
  say "Docker already installed -- skipping"
else
  say "Installing prerequisites"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl git

  say "Adding Docker's apt repository"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

  say "Installing Docker Engine"
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
                        docker-buildx-plugin docker-compose-plugin
fi

say "Verifying"
docker --version
docker compose version
systemctl is-active --quiet docker && echo "    daemon: running" || {
  echo "    daemon not running -- starting"; systemctl enable --now docker; }

# Let the login user run docker without sudo. Needs a new session to take effect,
# which is why the scripts below still use sudo.
TARGET_USER="${SUDO_USER:-ubuntu}"
if id "$TARGET_USER" >/dev/null 2>&1; then
  usermod -aG docker "$TARGET_USER" && echo "    added ${TARGET_USER} to the docker group"
fi

echo ""
say "Docker ready -- next: sudo ./20-fetch-supabase.sh"
