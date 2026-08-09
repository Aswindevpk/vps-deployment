#!/usr/bin/env bash
# Test and reload the global-nginx container configuration.
# Usage: ./scripts/reload-nginx.sh

set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-global-nginx}"

echo "==> Testing nginx configuration in ${CONTAINER_NAME}..."
if ! docker exec "${CONTAINER_NAME}" nginx -t; then
  echo "ERROR: nginx -t failed. Configuration was NOT reloaded." >&2
  exit 1
fi

echo "==> Reloading nginx..."
docker exec "${CONTAINER_NAME}" nginx -s reload

echo "==> Reload complete."
