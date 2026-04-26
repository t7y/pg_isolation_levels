#!/usr/bin/env bash
set -euo pipefail

# Load .env if present so POSTGRES_USER / POSTGRES_DB are available locally.
if [ -f "$(dirname "$0")/../.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$(dirname "$0")/../.env"
  set +a
fi

docker compose exec -it postgres \
  psql -U "${POSTGRES_USER:-lab}" -d "${POSTGRES_DB:-isolation_lab}"
