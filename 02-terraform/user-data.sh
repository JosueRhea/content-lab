#!/usr/bin/env bash
# Rendered by Terraform templatefile().
#   Escaping rule: only a literal $-brace needs doubling ($$-brace).
#   Plain $(cmd) and $VAR are passed through untouched -- do NOT double them,
#   or bash reads $$ as the PID and the whole boot silently breaks.
set -euo pipefail
exec > >(tee -a /var/log/supabase-boot.log) 2>&1
echo "==> boot started $(date -Is)"

export DEBIAN_FRONTEND=noninteractive
INSTALL_ROOT=/mnt/supabase-data

# ---------------------------------------------------------------- packages ---
apt-get update -qq
apt-get install -y -qq ca-certificates curl git jq unzip
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Arch-aware so swapping to a Graviton (t4g) instance type still boots.
CLI_ARCH="$(uname -m)"   # x86_64 | aarch64 -- both are valid AWS CLI URLs
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$${CLI_ARCH}.zip" -o /tmp/awscli.zip
unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install --update >/dev/null

# ------------------------------------------------------------- data volume ---
# Nitro ignores the device_name we asked for, so resolve by volume ID instead.
# ("vol-0abc" -> "vol0abc" in the by-id path.)
VOL_SHORT="$(echo "${data_volume_id}" | tr -d '-')"
DEV="/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_$${VOL_SHORT}"

echo "==> waiting for data volume $${DEV}"
for _ in $(seq 1 60); do [[ -e "$DEV" ]] && break; sleep 3; done

if [[ -e "$DEV" ]]; then
  # Only format when there is no filesystem -- otherwise we would wipe the DB on
  # every boot, which is the exact opposite of the point.
  if ! blkid "$DEV" >/dev/null 2>&1; then
    echo "==> fresh volume, creating filesystem"
    mkfs -t ext4 "$DEV"
  else
    echo "==> existing filesystem found, preserving data"
  fi
  mkdir -p "$INSTALL_ROOT"
  echo "$DEV $INSTALL_ROOT ext4 defaults,nofail 0 2" >> /etc/fstab
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
git -C "$REPO" fetch --depth 1 origin "${supabase_commit}"
git -C "$REPO" checkout --detach FETCH_HEAD
echo "==> supabase pinned at $(git -C "$REPO" rev-parse --short HEAD)"

cd "$REPO/docker"
cp -n .env.example .env

# ----------------------------------------------------------------- secrets ---
# Credentials come from Secrets Manager via the instance role. They were never on
# anyone's laptop and they are not in this file.
SECRET_JSON="$(aws secretsmanager get-secret-value \
  --secret-id "${secret_arn}" --region "${region}" --query SecretString --output text)"

JWT_SECRET="$(jq -r .JWT_SECRET        <<<"$SECRET_JSON")"
PG_PASS="$(jq -r .POSTGRES_PASSWORD    <<<"$SECRET_JSON")"
SKB="$(jq -r .SECRET_KEY_BASE          <<<"$SECRET_JSON")"
VEK="$(jq -r .VAULT_ENC_KEY            <<<"$SECRET_JSON")"
DASH_USER="$(jq -r .DASHBOARD_USERNAME <<<"$SECRET_JSON")"
DASH_PASS="$(jq -r .DASHBOARD_PASSWORD <<<"$SECRET_JSON")"

# Terraform has no HMAC function, so the anon/service_role JWTs get signed here at
# boot. They exist only on this box and in nobody's shell history.
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
set_env DASHBOARD_USERNAME "$DASH_USER"
set_env DASHBOARD_PASSWORD "$DASH_PASS"

# The Elastic IP is known before the instance boots, so the public URLs are right
# on the first try. In the manual demo, this was trap #2.
set_env SITE_URL            "http://${public_host}:8000"
set_env API_EXTERNAL_URL    "http://${public_host}:8000"
set_env SUPABASE_PUBLIC_URL "http://${public_host}:8000"

chmod 600 .env

# -------------------------------------------------------------------- up -----
echo "==> pulling images (this is the slow part)"
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
