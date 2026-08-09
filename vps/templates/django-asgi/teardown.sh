#!/usr/bin/env bash
# Complete removal of a native VPS Silo-style app.
#
# Stops systemd, removes Nginx site, deletes app files, and optionally
# drops the PostgreSQL database/role. Redis keys are left intact unless
# you flush them manually.
#
# Usage:
#   sudo ./teardown.sh
#   sudo APP_NAME=silo APP_DOMAIN=api.example.com DROP_DATABASE=1 ./teardown.sh
#
# Environment:
#   APP_NAME       default: silo
#   APP_ROOT       default: /var/www/$APP_NAME
#   SERVICE_NAME   default: ${APP_NAME}-gunicorn.service
#   NGINX_SITE     default: ${APP_NAME}-api
#   APP_DOMAIN     default: api.example.com (for certbot delete prompt)
#   DROP_DATABASE  set to 1 to drop Postgres DB + role named $APP_NAME
#   DELETE_CERTS   set to 1 to attempt certbot delete for $APP_DOMAIN

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root (sudo ./teardown.sh)" >&2
  exit 1
fi

APP_NAME="${APP_NAME:-silo}"
APP_ROOT="${APP_ROOT:-/var/www/${APP_NAME}}"
SERVICE_NAME="${SERVICE_NAME:-${APP_NAME}-gunicorn.service}"
NGINX_SITE="${NGINX_SITE:-${APP_NAME}-api}"
APP_DOMAIN="${APP_DOMAIN:-api.example.com}"
DROP_DATABASE="${DROP_DATABASE:-0}"
DELETE_CERTS="${DELETE_CERTS:-0}"

log() { printf '==> %s\n' "$*"; }

log "Stopping and disabling ${SERVICE_NAME}..."
systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
rm -f "/etc/systemd/system/${SERVICE_NAME}"
systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

log "Removing Nginx site ${NGINX_SITE}..."
rm -f "/etc/nginx/sites-enabled/${NGINX_SITE}.conf"
rm -f "/etc/nginx/sites-available/${NGINX_SITE}.conf"
# Legacy filename from the blueprint
rm -f /etc/nginx/sites-enabled/silo-api.conf
rm -f /etc/nginx/sites-available/silo-api.conf

if nginx -t 2>/dev/null; then
  systemctl reload nginx
else
  log "WARNING: nginx -t failed after site removal — fix remaining configs manually"
fi

if [[ "${DELETE_CERTS}" == "1" ]]; then
  log "Deleting Let's Encrypt certificate for ${APP_DOMAIN}..."
  certbot delete --cert-name "${APP_DOMAIN}" --non-interactive 2>/dev/null || \
    log "certbot delete skipped or failed (cert may not exist)"
fi

if [[ "${DROP_DATABASE}" == "1" ]]; then
  log "Dropping PostgreSQL database and role ${APP_NAME}..."
  sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${APP_NAME}' AND pid <> pg_backend_pid();
DROP DATABASE IF EXISTS ${APP_NAME};
DROP ROLE IF EXISTS ${APP_NAME};
SQL
fi

if [[ -d "${APP_ROOT}" ]]; then
  log "Removing application directory ${APP_ROOT}..."
  rm -rf "${APP_ROOT}"
else
  log "APP_ROOT not found (${APP_ROOT}) — skipping directory removal"
fi

log "Teardown complete for ${APP_NAME}."
log "Remaining manual checks: Redis DB indexes, DNS records, CI deploy secrets."
