#!/usr/bin/env bash
set -euo pipefail

if [ -f "$(dirname "$0")/../.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$(dirname "$0")/../.env"
  set +a
fi

docker compose exec -T postgres \
  psql -U "${POSTGRES_USER:-lab}" -d "${POSTGRES_DB:-isolation_lab}" \
  -f /sql/reset.sql
echo "Reset complete."
