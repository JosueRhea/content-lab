#!/usr/bin/env bash
# Step 00 -- run FIRST, before installing anything.
# Checks only what would waste your time later: too little RAM, too little disk,
# wrong OS. Deliberately does not check Docker; that is step 10's job.
set -uo pipefail
say(){ printf '\033[1m==>\033[0m %s\n' "$*"; }
bad(){ printf '    \033[31mFAIL\033[0m %s\n' "$*"; FAIL=1; }
warn(){ printf '    \033[33mWARN\033[0m %s\n' "$*"; }
ok(){ printf '    \033[32mok\033[0m   %s\n' "$*"; }
FAIL=0

say "Preflight"

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  case "${ID:-}" in
    ubuntu) ok "OS: ${PRETTY_NAME}" ;;
    debian) warn "OS: ${PRETTY_NAME} -- step 10 targets Ubuntu; apt repo line differs" ;;
    *)      bad "OS: ${PRETTY_NAME:-unknown} -- these scripts target Ubuntu 24.04" ;;
  esac
else
  bad "cannot read /etc/os-release"
fi

MEM_MB=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
if [[ -n "${MEM_MB:-}" ]]; then
  if   [[ $MEM_MB -lt 1900 ]]; then bad "RAM: ${MEM_MB}MB -- ~13 containers will OOM. Use t3.medium."
  elif [[ $MEM_MB -lt 3800 ]]; then warn "RAM: ${MEM_MB}MB -- tight but workable; will feel sluggish."
  else ok "RAM: ${MEM_MB}MB"; fi
fi

DISK_GB=$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')
if [[ -n "${DISK_GB:-}" ]]; then
  if [[ $DISK_GB -lt 12 ]]; then bad "Disk: ${DISK_GB}GB free -- images alone are ~8GB. Use 30GB gp3."
  else ok "Disk: ${DISK_GB}GB free"; fi
fi

ARCH=$(uname -m); ok "Arch: ${ARCH}"

if curl -fsS --max-time 8 -o /dev/null https://registry-1.docker.io/v2/ 2>/dev/null; then
  ok "Docker Hub reachable"
else
  # 401 without a token is normal here; only a hard network failure matters.
  curl -fsS --max-time 8 -o /dev/null -w '' https://download.docker.com/ 2>/dev/null \
    && ok "outbound HTTPS working" || bad "no outbound HTTPS -- check the security group / route table"
fi

echo ""
if [[ $FAIL -eq 0 ]]; then say "Preflight OK -- next: sudo ./10-install-docker.sh"; else
  say "Preflight FAILED -- fix the above before continuing"; exit 1; fi
