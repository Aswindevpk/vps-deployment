#!/usr/bin/env bash
# One-click VPS bootstrap for the native (non-Docker) paradigm.
# Installs Nginx, PostgreSQL, Redis, Certbot, UFW, and Astral uv.
#
# Usage (as root or with sudo):
#   sudo ./setup-vps-environment.sh
#
# Safe to re-run: package installs and enablement are idempotent where possible.

set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root (sudo ./setup-vps-environment.sh)" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "==> Updating apt indexes and upgrading packages..."
apt-get update -y
apt-get upgrade -y

echo "==> Installing base packages..."
apt-get install -y \
  curl \
  ca-certificates \
  gnupg \
  git \
  ufw \
  nginx \
  postgresql \
  postgresql-contrib \
  redis-server \
  certbot \
  python3-certbot-nginx \
  build-essential \
  libpq-dev \
  python3-dev

echo "==> Enabling and starting Redis..."
systemctl enable redis-server
systemctl start redis-server

echo "==> Enabling and starting PostgreSQL..."
systemctl enable postgresql
systemctl start postgresql

echo "==> Enabling and starting Nginx..."
systemctl enable nginx
systemctl start nginx

echo "==> Configuring UFW (22/80/443)..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "==> Installing Astral uv for deploy user (or root fallback)..."
DEPLOY_HOME="$(getent passwd deploy | cut -d: -f6 || true)"
if [[ -n "${DEPLOY_HOME}" && -d "${DEPLOY_HOME}" ]]; then
  sudo -u deploy bash -lc 'curl -fsSL https://astral.sh/uv/install.sh | bash'
  echo "uv installed for user deploy (see ${DEPLOY_HOME}/.local/bin/uv)"
else
  curl -fsSL https://astral.sh/uv/install.sh | bash
  echo "uv installed for root (create a deploy user and re-run uv install for that user)"
fi

echo "==> Ensuring /var/www exists..."
mkdir -p /var/www
if id deploy &>/dev/null; then
  chown deploy:deploy /var/www
fi

echo "==> Ensuring Certbot webroot exists..."
mkdir -p /var/www/certbot
if id deploy &>/dev/null; then
  chown -R deploy:www-data /var/www/certbot
fi

echo ""
echo "Bootstrap complete."
echo "  nginx:      $(nginx -v 2>&1)"
echo "  postgres:   $(psql --version 2>/dev/null || true)"
echo "  redis:      $(redis-server --version 2>/dev/null || true)"
echo "  certbot:    $(certbot --version 2>/dev/null || true)"
echo "  uv:         $(sudo -u deploy bash -lc 'command -v uv && uv --version' 2>/dev/null || command -v uv || echo 'install for deploy user')"
echo ""
echo "Next: follow vps/README.md to deploy an app from templates/django-asgi/."
