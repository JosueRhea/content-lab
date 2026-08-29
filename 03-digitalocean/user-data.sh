#!/usr/bin/env bash
# Rendered by Terraform templatefile().
#   Escaping rule: only a literal $-brace needs doubling ($$-brace).
#   Plain $(cmd) and $VAR pass through untouched -- do NOT double them,
#   or bash reads $$ as the PID and the boot silently breaks.
set -euo pipefail
exec > >(tee -a /var/log/supabase-boot.log) 2>&1
echo "==> boot started $(date -Is)"

export DEBIAN_FRONTEND=noninteractive
INSTALL_ROOT=/mnt/supabase-data

# ---------------------------------------------------------------- packages ---
# No AWS CLI here: nothing to authenticate to. Secrets arrived with this script.
apt-get update -qq
apt-get install -y -qq ca-certificates curl git
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ------------------------------------------------------------- data volume ---
# DO exposes volumes by name rather than by ID (AWS used the volume ID).
DEV="/dev/disk/by-id/scsi-0DO_Volume_${volume_name}"

echo "==> waiting for volume $${DEV}"
for _ in $(seq 1 60); do [[ -e "$DEV" ]] && break; sleep 3; done

if [[ -e "$DEV" ]]; then
  # DO pre-formats via initial_filesystem_type, but never assume -- and never
  # reformat, or every boot wipes the database.
  if ! blkid "$DEV" >/dev/null 2>&1; then
    echo "==> no filesystem found, creating one"
    mkfs -t ext4 "$DEV"
  else
    echo "==> existing filesystem found, preserving data"
  fi
  mkdir -p "$INSTALL_ROOT"
  echo "$DEV $INSTALL_ROOT ext4 defaults,nofail,discard 0 2" >> /etc/fstab
  mount "$INSTALL_ROOT"
else
  echo "!! volume never attached; falling back to root disk (data will NOT survive)"
  mkdir -p "$INSTALL_ROOT"
fi

# ---------------------------------------------------------------- supabase ---
REPO="$INSTALL_ROOT/supabase"
if [[ ! -d "$REPO/.git" ]]; then
  git clone --filter=blob:none --no-checkout https://github.com/supabase/supabase.git "$REPO"
  git -C "$REPO" sparse-checkout set --cone docker
fi
# HEAD works whatever upstream calls its default branch (supabase uses master).
if ! git -C "$REPO" fetch --depth 1 origin "${supabase_commit}"; then
  echo "!! cannot fetch ref '${supabase_commit}' -- use HEAD or a real SHA" >&2
  exit 1
fi
git -C "$REPO" checkout --detach FETCH_HEAD
[[ -d "$REPO/docker" ]] || { echo "!! no docker/ after checkout -- wrong ref" >&2; exit 1; }
echo "==> supabase pinned at $(git -C "$REPO" rev-parse --short HEAD)"

cd "$REPO/docker"
cp -n .env.example .env

# ----------------------------------------------------------------- secrets ---
# Interpolated straight into this file by Terraform, because DigitalOcean has no
# instance identity to authenticate with and no secret manager for droplets.
#
# Consequence, and say it out loud on camera: these values stay readable for the
# life of the droplet at http://169.254.169.254/metadata/v1/user-data -- to any
# process on the box, not just root.
JWT_SECRET="${jwt_secret}"
PG_PASS="${postgres_password}"
SKB="${secret_key_base}"
VEK="${vault_enc_key}"
DASH_PASS="${dashboard_password}"

# JWT signing is identical to the AWS build: Terraform has no HMAC function on
# any provider, so the anon/service_role keys get derived here either way.
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
sign_jwt() {
  local claims="$1" header payload sig
  header="$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | b64url)"
  payload="$(printf '%s' "$claims" | b64url)"
  sig="$(printf '%s' "$${header}.$${payload}" \
        | openssl dgst -sha256 -hmac "$JWT_SECRET" -binary | b64url)"
  printf '%s.%s.%s' "$header" "$payload" "$sig"
}
IAT="$(date +%s)"; EXP="$(( IAT + 60*60*24*365*10 ))"
ANON_KEY="$(sign_jwt "{\"role\":\"anon\",\"iss\":\"supabase\",\"iat\":$${IAT},\"exp\":$${EXP}}")"
SERVICE_KEY="$(sign_jwt "{\"role\":\"service_role\",\"iss\":\"supabase\",\"iat\":$${IAT},\"exp\":$${EXP}}")"

# ------------------------------------------------------------------- .env ----
set_env() {
  local key="$1" val="$2"
  if grep -qE "^$${key}=" .env; then
    sed -i -E "s|^$${key}=.*|$${key}=$${val}|" .env
  else
    printf '%s=%s\n' "$key" "$val" >> .env
  fi
}

set_env POSTGRES_PASSWORD  "$PG_PASS"
set_env JWT_SECRET         "$JWT_SECRET"
set_env ANON_KEY           "$ANON_KEY"
set_env SERVICE_ROLE_KEY   "$SERVICE_KEY"
set_env SECRET_KEY_BASE    "$SKB"
set_env VAULT_ENC_KEY      "$VEK"
set_env DASHBOARD_USERNAME "supabase"
set_env DASHBOARD_PASSWORD "$DASH_PASS"

# The reserved IP was allocated before this droplet existed, so these are right
# on the first boot -- exactly as on AWS. This part of the design ported cleanly.
set_env SITE_URL            "http://${public_host}:8000"
set_env API_EXTERNAL_URL    "http://${public_host}:8000"
set_env SUPABASE_PUBLIC_URL "http://${public_host}:8000"

chmod 600 .env

# -------------------------------------------------------------------- up -----
echo "==> pulling images (the slow part)"
docker compose pull --quiet
echo "==> starting"
docker compose up -d

cat > /etc/systemd/system/supabase.service <<UNIT
[Unit]
Description=Supabase self-hosted
Requires=docker.service
After=docker.service network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$REPO/docker
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
[Install]
WantedBy=multi-user.target
UNIT
systemctl enable supabase.service

echo "==> DONE $(date -Is) -- http://${public_host}:8000"
