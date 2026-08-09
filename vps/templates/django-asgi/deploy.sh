#!/usr/bin/env bash
# Bare-metal deployment for the Silo Django ASGI blueprint.
#
# Expected layout on the VPS:
#   /var/www/silo              — application checkout
#   /var/www/silo/.venv        — uv-managed virtualenv
#   /var/www/silo/.env         — secrets (not in git)
#   systemd unit               — silo-gunicorn.service
#
# Usage (as deploy, from the app directory or via CI):
#   ./deploy.sh
#   APP_ROOT=/var/www/silo ./deploy.sh
#
# Environment overrides:
#   APP_ROOT, APP_NAME, SERVICE_NAME, BRANCH, PYTHON_VERSION

set -euo pipefail

APP_NAME="${APP_NAME:-silo}"
APP_ROOT="${APP_ROOT:-/var/www/${APP_NAME}}"
SERVICE_NAME="${SERVICE_NAME:-${APP_NAME}-gunicorn.service}"
BRANCH="${BRANCH:-main}"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v uv >/dev/null 2>&1 || die "uv not found in PATH (install via vps/setup-vps-environment.sh)"

[[ -d "${APP_ROOT}" ]] || die "APP_ROOT does not exist: ${APP_ROOT}"
cd "${APP_ROOT}"

if [[ -d .git ]]; then
  log "Fetching and resetting to origin/${BRANCH}..."
  git fetch --prune origin
  git checkout "${BRANCH}"
  git reset --hard "origin/${BRANCH}"
else
  log "No .git directory — deploying current tree at ${APP_ROOT}"
fi

log "Syncing Python environment with uv (Python ${PYTHON_VERSION})..."
uv python install "${PYTHON_VERSION}" >/dev/null 2>&1 || true
uv sync --frozen --no-dev || uv sync --no-dev

if [[ -f manage.py ]]; then
  log "Running database migrations..."
  uv run python manage.py migrate --noinput
  log "Collecting static files..."
  uv run python manage.py collectstatic --noinput
fi

# Ensure nginx (www-data) can traverse to and connect the Unix socket
log "Fixing ownership and socket directory permissions..."
sudo chown -R deploy:www-data "${APP_ROOT}"
sudo find "${APP_ROOT}" -type d -exec chmod 750 {} \;
# Socket file is created by gunicorn with umask 007 → deploy:www-data, mode 660

if systemctl list-unit-files "${SERVICE_NAME}" --no-legend 2>/dev/null | grep -q "${SERVICE_NAME}"; then
  log "Reloading systemd unit ${SERVICE_NAME}..."
  sudo systemctl daemon-reload
  sudo systemctl restart "${SERVICE_NAME}"
  sudo systemctl --no-pager --full status "${SERVICE_NAME}" || true
else
  log "WARNING: ${SERVICE_NAME} not installed yet."
  log "Copy systemd/silo-gunicorn.service to /etc/systemd/system/${SERVICE_NAME}, then:"
  log "  sudo systemctl daemon-reload && sudo systemctl enable --now ${SERVICE_NAME}"
fi

if [[ -f /etc/nginx/sites-enabled/${APP_NAME}-api.conf ]] || [[ -f /etc/nginx/sites-enabled/silo-api.conf ]]; then
  log "Testing and reloading Nginx..."
  sudo nginx -t
  sudo systemctl reload nginx
fi

log "Deploy complete."
