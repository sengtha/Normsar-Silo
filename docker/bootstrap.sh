#!/usr/bin/env bash
#
# Normsar Silo — one-time secret generator.
#
# Produces a ready-to-run .env from .env.example: a random Postgres password,
# JWT secret, dashboard password, encryption keys, and the derived Supabase
# ANON_KEY / SERVICE_ROLE_KEY (HS256 JWTs signed with the generated JWT
# secret). Also wires the public URLs to your domain.
#
# Usage:
#   ./bootstrap.sh --domain silo.example.com --email you@example.com
#   ./bootstrap.sh --domain localhost                 # local trial
#   ./bootstrap.sh ... --force                        # overwrite existing .env
#
# Requires: bash 4+, openssl. Nothing else — safe to run on a bare VM.

set -euo pipefail
cd "$(dirname "$0")"

DOMAIN=""
EMAIL=""
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2 ;;
    --email)  EMAIL="$2";  shift 2 ;;
    --force)  FORCE=1;     shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

command -v openssl >/dev/null 2>&1 || { echo "ERROR: openssl is required." >&2; exit 1; }
[ -f .env.example ] || { echo "ERROR: run this from the docker/ directory (.env.example not found)." >&2; exit 1; }
if [ -f .env ] && [ "$FORCE" -ne 1 ]; then
  echo "ERROR: .env already exists. Re-run with --force to regenerate (this rotates ALL secrets)." >&2
  exit 1
fi

if [ -z "$DOMAIN" ]; then
  read -r -p "Public domain for this Silo (or 'localhost' for a local trial): " DOMAIN
fi
[ -n "$DOMAIN" ] || { echo "ERROR: a domain is required." >&2; exit 1; }
if [ "$DOMAIN" != "localhost" ] && [ -z "$EMAIL" ]; then
  read -r -p "Email for Let's Encrypt certificate notices: " EMAIL
fi

# --- helpers ----------------------------------------------------------------
rand()  { openssl rand -hex "${1:-24}"; }
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# Mint an HS256 JWT: mint_jwt <role>  ->  a Supabase legacy API key.
mint_jwt() {
  local role="$1" iat exp header payload h p sig
  iat=$(date +%s)
  exp=$((iat + 3600 * 24 * 3650))   # ~10 years
  header='{"alg":"HS256","typ":"JWT"}'
  payload="{\"role\":\"${role}\",\"iss\":\"supabase\",\"iat\":${iat},\"exp\":${exp}}"
  h=$(printf '%s' "$header"  | b64url)
  p=$(printf '%s' "$payload" | b64url)
  sig=$(printf '%s' "$h.$p" | openssl dgst -sha256 -hmac "$JWT_SECRET" -binary | b64url)
  printf '%s.%s.%s' "$h" "$p" "$sig"
}

# --- generate secrets -------------------------------------------------------
JWT_SECRET="$(rand 32)"                       # 64 hex chars, > 32 required
POSTGRES_PASSWORD="$(rand 24)"
DASHBOARD_PASSWORD="$(rand 12)"
SECRET_KEY_BASE="$(rand 32)"
VAULT_ENC_KEY="$(rand 16)"                    # 32 chars
PG_META_CRYPTO_KEY="$(rand 16)"               # 32 chars
LOGFLARE_PUBLIC_ACCESS_TOKEN="$(rand 24)"
LOGFLARE_PRIVATE_ACCESS_TOKEN="$(rand 24)"
POOLER_TENANT_ID="silo-$(rand 4)"
S3_PROTOCOL_ACCESS_KEY_ID="$(rand 16)"
S3_PROTOCOL_ACCESS_KEY_SECRET="$(rand 32)"
ANON_KEY="$(mint_jwt anon)"
SERVICE_ROLE_KEY="$(mint_jwt service_role)"

if [ "$DOMAIN" = "localhost" ]; then
  PUBLIC_URL="https://localhost:8443"
else
  PUBLIC_URL="https://${DOMAIN}"
fi

# Keys we override in .env (everything else keeps the .env.example default).
declare -A V=(
  [POSTGRES_PASSWORD]="$POSTGRES_PASSWORD"
  [JWT_SECRET]="$JWT_SECRET"
  [ANON_KEY]="$ANON_KEY"
  [SERVICE_ROLE_KEY]="$SERVICE_ROLE_KEY"
  [DASHBOARD_PASSWORD]="$DASHBOARD_PASSWORD"
  [SECRET_KEY_BASE]="$SECRET_KEY_BASE"
  [VAULT_ENC_KEY]="$VAULT_ENC_KEY"
  [PG_META_CRYPTO_KEY]="$PG_META_CRYPTO_KEY"
  [LOGFLARE_PUBLIC_ACCESS_TOKEN]="$LOGFLARE_PUBLIC_ACCESS_TOKEN"
  [LOGFLARE_PRIVATE_ACCESS_TOKEN]="$LOGFLARE_PRIVATE_ACCESS_TOKEN"
  [POOLER_TENANT_ID]="$POOLER_TENANT_ID"
  [S3_PROTOCOL_ACCESS_KEY_ID]="$S3_PROTOCOL_ACCESS_KEY_ID"
  [S3_PROTOCOL_ACCESS_KEY_SECRET]="$S3_PROTOCOL_ACCESS_KEY_SECRET"
  [SILO_DOMAIN]="$DOMAIN"
  [CADDY_ACME_EMAIL]="$EMAIL"
  # Public-facing URLs — must match the domain for auth redirects to work.
  [SUPABASE_PUBLIC_URL]="$PUBLIC_URL"
  [API_EXTERNAL_URL]="$PUBLIC_URL"
  [SITE_URL]="$PUBLIC_URL"
  # Keep Kong's raw ports bound to loopback; only Caddy is public.
  [KONG_HTTP_PORT]="127.0.0.1:8000"
  [KONG_HTTPS_PORT]="127.0.0.1:8443"
)

# Rewrite .env.example -> .env, substituting the keys above.
: > .env
while IFS= read -r line || [ -n "$line" ]; do
  key="${line%%=*}"
  if [[ "$line" == *"="* ]] && [[ -n "${V[$key]+x}" ]]; then
    printf '%s=%s\n' "$key" "${V[$key]}"
  else
    printf '%s\n' "$line"
  fi
done < .env.example > .env
chmod 600 .env

echo
echo "✅  Wrote .env for domain: ${DOMAIN}"
echo "    Dashboard login:  ${DASHBOARD_USERNAME:-supabase} / ${DASHBOARD_PASSWORD}"
echo
echo "Next:"
echo "  1. (optional) add GEMINI_API_KEY, HUB_URL, HUB_SILO_API_KEY, etc. to .env"
echo "  2. docker compose up -d"
echo "  3. Apply is automatic — the Silo schema loads on first boot."
if [ "$DOMAIN" != "localhost" ]; then
  echo "  4. Point ${DOMAIN} A record at this VM and open ports 80 + 443."
fi
