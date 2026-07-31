#!/usr/bin/env bash
#
# Normsar Silo — one-command installer.
#
# Stands up a complete, sovereign Silo on a fresh Linux VM straight from
# GitHub: installs Docker, clones this repository, generates all secrets, and
# brings the stack up behind automatic HTTPS. You run it on YOUR server — the
# Silo stays entirely under your control.
#
# Usage (on a fresh Ubuntu/Debian VM, as root or with sudo):
#
#   curl -fsSL https://raw.githubusercontent.com/sengtha/Normsar-Silo/main/install.sh \
#     | sudo bash -s -- --domain silo.example.com --email you@example.com
#
# Re-running updates an existing install in place (git pull + recreate).
#
# Options:
#   --domain <host>   Public domain for the Silo (required; DNS A record → this VM).
#   --email  <addr>   Email for Let's Encrypt certificate notices (required for a real domain).
#   --repo   <o/r>    GitHub repo to install from (default: sengtha/Normsar-Silo).
#   --branch <name>   Branch to install (default: main).
#   --dir    <path>   Install directory (default: /opt/normsar-silo).
#   --force           Regenerate .env even if it already exists (rotates ALL secrets).
#
# Optional feature keys may be supplied as environment variables and are written
# into .env automatically: GEMINI_API_KEY, HUB_URL, HUB_SILO_API_KEY,
# HUB_PUBLISHABLE_KEY, CF_DO_URL, CF_DO_SECRET_KEY, LIT_API_KEY, LIT_PKP_PUBLIC_KEY.

set -euo pipefail

REPO="sengtha/Normsar-Silo"
BRANCH="main"
DIR="/opt/normsar-silo"
DOMAIN=""
EMAIL=""
FORCE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2 ;;
    --email)  EMAIL="$2";  shift 2 ;;
    --repo)   REPO="$2";   shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --dir)    DIR="$2";    shift 2 ;;
    --force)  FORCE="--force"; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

log() { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

[ -n "$DOMAIN" ] || die "A domain is required: --domain silo.example.com"

# Need root to install Docker and write under /opt. Every documented path pipes
# into `sudo bash`, so just require it (avoids a fragile re-exec when the script
# is read from stdin).
if [ "$(id -u)" -ne 0 ]; then
  die "Please run as root — prepend sudo, e.g.
    curl -fsSL https://raw.githubusercontent.com/${REPO}/${BRANCH}/install.sh | sudo bash -s -- --domain ${DOMAIN} --email you@example.com"
fi

# --- 1. Docker -------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker…"
  curl -fsSL https://get.docker.com | sh
fi
if ! docker compose version >/dev/null 2>&1; then
  die "Docker Compose v2 is required (the Docker install above normally includes it)."
fi
systemctl enable --now docker >/dev/null 2>&1 || true

# --- 2. Source ------------------------------------------------------------
if [ -d "$DIR/.git" ]; then
  log "Updating existing install at $DIR…"
  git -C "$DIR" fetch --depth 1 origin "$BRANCH"
  git -C "$DIR" checkout -q "$BRANCH"
  git -C "$DIR" reset --hard "origin/$BRANCH"
else
  log "Cloning $REPO ($BRANCH) → $DIR…"
  command -v git >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq git; }
  git clone --depth 1 --branch "$BRANCH" "https://github.com/${REPO}.git" "$DIR"
fi

cd "$DIR/docker"

# --- 3. Secrets / .env ----------------------------------------------------
if [ ! -f .env ] || [ -n "$FORCE" ]; then
  log "Generating secrets for $DOMAIN…"
  bash bootstrap.sh --domain "$DOMAIN" ${EMAIL:+--email "$EMAIL"} $FORCE
else
  log ".env already exists — keeping it (pass --force to rotate secrets)."
fi

# Write any optional feature keys passed via environment into .env.
setenv() {
  local key="$1" val="${2:-}"
  [ -n "$val" ] || return 0
  if grep -q "^${key}=" .env; then
    # Use a temp file to avoid sed escaping issues with slashes / special chars.
    awk -v k="$key" -v v="$val" 'BEGIN{FS=OFS="="} $1==k{$0=k"="v} {print}' .env > .env.tmp && mv .env.tmp .env
  else
    printf '%s=%s\n' "$key" "$val" >> .env
  fi
  echo "  set ${key}"
}
if [ -n "${GEMINI_API_KEY:-}${HUB_URL:-}${HUB_SILO_API_KEY:-}${HUB_PUBLISHABLE_KEY:-}${CF_DO_URL:-}${CF_DO_SECRET_KEY:-}${LIT_API_KEY:-}${LIT_PKP_PUBLIC_KEY:-}" ]; then
  log "Applying optional feature keys from environment…"
  setenv GEMINI_API_KEY       "${GEMINI_API_KEY:-}"
  setenv HUB_URL              "${HUB_URL:-}"
  setenv HUB_SILO_API_KEY     "${HUB_SILO_API_KEY:-}"
  setenv HUB_PUBLISHABLE_KEY  "${HUB_PUBLISHABLE_KEY:-}"
  setenv CF_DO_URL            "${CF_DO_URL:-}"
  setenv CF_DO_SECRET_KEY     "${CF_DO_SECRET_KEY:-}"
  setenv LIT_API_KEY          "${LIT_API_KEY:-}"
  setenv LIT_PKP_PUBLIC_KEY   "${LIT_PKP_PUBLIC_KEY:-}"
fi

# --- 4. Launch ------------------------------------------------------------
log "Starting the Silo (docker compose up -d)…"
docker compose pull --quiet 2>/dev/null || true
docker compose up -d

echo
printf '\033[1;32m✓ Normsar Silo is starting.\033[0m\n'
echo "  Domain:     https://${DOMAIN}"
echo "  Install:    ${DIR}"
echo
echo "Next:"
echo "  1. Point ${DOMAIN}'s DNS A record at this server and open ports 80 + 443."
echo "  2. Watch it come up:   cd ${DIR}/docker && docker compose logs -f"
echo "  3. Register the Silo with the Hub (Silo Manager) using your Project URL"
echo "     (https://${DOMAIN}) and Anon Key (see ${DIR}/docker/.env: ANON_KEY)."
