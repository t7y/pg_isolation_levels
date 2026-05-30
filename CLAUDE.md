# CLAUDE.md

This file provides guidance for working with this repository — a hands-on lab for exploring PostgreSQL transaction isolation levels.

## Purpose

A self-contained sandbox for running interactive demos that illustrate PostgreSQL's isolation levels (Read Committed, Repeatable Read, Serializable) and the anomalies they do and don't prevent. The repo is meant to be cloned, brought up with a single command, and explored with two `psql` sessions side by side.

## Stack

- **PostgreSQL 16** running in Docker via `docker compose`
- **psql** (host or containerized) as the primary interaction tool
- No application code — this is a pure SQL learning environment

## Repository Layout

```
.
├── CLAUDE.md
├── README.md
├── docker-compose.yml
├── .env.example
├── sql/
│   ├── 00_setup.sql            # Creates tables and seed data for all demos
│   ├── 01_read_committed.sql   # Demo 1: non-repeatable reads
│   ├── 02_repeatable_read.sql  # Demo 2: snapshot isolation + 40001 on write conflict
│   ├── 03_write_skew.sql       # Demo 3: RR doesn't prevent write skew (doctors)
│   ├── 04_serializable.sql     # Demo 4: SSI catches write skew
│   ├── 05_for_update.sql       # Demo 5: RC + FOR UPDATE escape hatch
│   ├── 06_balance_transfer.sql # Demo 6: balance race condition
│   └── reset.sql               # Resets all demo tables to initial state
├── scripts/
│   ├── psql.sh                 # Opens a psql session against the container
│   └── reset.sh                # Convenience wrapper for sql/reset.sql
├── .cursor/                    # Interactive in-Cursor walkthrough (see below)
│   ├── rules/course-instructor.mdc  # Always-on instructor persona
│   ├── SCRIPT_INSTRUCTIONS.md       # Verbatim teaching-script rules (STOP/ACTION/USER)
│   └── commands/                    # /start-setup, /start-1 … /start-6 slash commands
├── lessons/                    # Teaching scripts the slash commands load
│   ├── 00-setup/SCRIPT.md
│   └── 01-read-committed/ … 06-balance-transfer/SCRIPT.md
└── website/                    # Nextra reference site (browsable handbook of the demos)
```

Each demo file is annotated with `-- SESSION 1` and `-- SESSION 2` markers indicating which session should run which block, and in what order.

## Interactive walkthrough (the `.cursor/` + `lessons/` layer)

The repo doubles as a self-teaching course inside Cursor. A learner types `/start-setup` then `/start-1` … `/start-6`; the always-on rule in `.cursor/rules/course-instructor.mdc` puts the AI in "instructor" mode, each slash command loads the matching `lessons/<n>/SCRIPT.md`, and the AI follows that script verbatim per `.cursor/SCRIPT_INSTRUCTIONS.md`.

**Guide-only, two-terminal model:** because the demos need two `psql` sessions held open across turns, the instructor never runs the interleaved SQL itself. It relays the exact statements from the `sql/` files (the single source of truth), tells the learner which session to paste into (Terminal 1 = Session 1, Terminal 2 = Session 2), and STOPs to wait for the observed output before continuing. The only commands the instructor may run itself are non-interactive one-shots (`docker compose up -d`, `./scripts/reset.sh`, etc.). When editing the teaching scripts, keep SQL relayed from `sql/` rather than duplicated, so the two stay in sync.

## Quick Start

```bash
cp .env.example .env
docker compose up -d
./scripts/psql.sh    # in two separate terminals for side-by-side demos
```

To reset between demos:

```bash
./scripts/reset.sh
```

To tear everything down (including data):

```bash
docker compose down -v
```

## docker-compose.yml

```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: pg-isolation-lab
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-lab}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-lab}
      POSTGRES_DB: ${POSTGRES_DB:-isolation_lab}
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./sql:/sql:ro
    command:
      - "postgres"
      - "-c"
      - "log_statement=all"
      - "-c"
      - "log_destination=stderr"
      - "-c"
      - "log_min_messages=notice"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-lab} -d ${POSTGRES_DB:-isolation_lab}"]
      interval: 2s
      timeout: 3s
      retries: 10

volumes:
  pgdata:
```

`log_statement=all` is intentional — it makes it easy to inspect the order in which statements arrive at the server when interleaving sessions. View with `docker compose logs -f postgres`.

## .env.example

```
POSTGRES_USER=lab
POSTGRES_PASSWORD=lab
POSTGRES_DB=isolation_lab
POSTGRES_PORT=5432
```

## scripts/psql.sh

```bash
#!/usr/bin/env bash
set -euo pipefail
docker compose exec -it postgres \
  psql -U "${POSTGRES_USER:-lab}" -d "${POSTGRES_DB:-isolation_lab}"
```

Make sure to `chmod +x scripts/*.sh` after creating these.

## scripts/reset.sh

```bash
#!/usr/bin/env bash
set -euo pipefail
docker compose exec -T postgres \
  psql -U "${POSTGRES_USER:-lab}" -d "${POSTGRES_DB:-isolation_lab}" \
  -f /sql/reset.sql
echo "Reset complete."
```

## How the Demos Are Structured

Every demo file follows the same pattern so the workflow stays muscle-memory:

1. **Top of file**: a one-paragraph description of the anomaly being demonstrated and the expected outcome.
2. **`-- SESSION 1`** and **`-- SESSION 2`** blocks, numbered in execution order (`-- STEP 1`, `-- STEP 2`, ...).
3. **`-- EXPECT:`** comments above each query showing the expected output.
4. **`-- TAKEAWAY:`** comment at the end summarizing what the demo proved.

When adding new demos, follow this convention. The point is for someone to be able to run a demo cold, without having to read prose, and still understand what they're seeing.

## Conventions for Modifying SQL

- All demos must be runnable from a freshly reset state — call `sql/reset.sql` at the top of each file or document the prerequisite explicitly.
- Use the existing tables (`counters`, `doctors`, `accounts`) where possible. Only add new tables to `00_setup.sql` if a demo genuinely needs new structure.
- Always set isolation level explicitly with `BEGIN ISOLATION LEVEL ...` rather than relying on session defaults — readers shouldn't have to remember context.
- Show `SQLSTATE` codes (especially `40001`) in expected output comments. The error codes are part of the lesson.
- Don't introduce application code unless a demo specifically requires retry-loop behavior. If retry logic is illustrated, keep it in a separate `examples/` directory and call it out clearly.

## What This Repo Is Not

- Not a benchmark suite — no pgbench, no load generation.
- Not a Postgres tuning guide — `postgresql.conf` settings beyond logging are intentionally left at defaults so behavior matches what readers will see in their own environments.
- Not a Prisma/ORM tutorial — pure SQL keeps the focus on server-side semantics.

## Useful Commands

```bash
# Watch statements as they arrive (great for understanding interleaving)
docker compose logs -f postgres

# Inspect locks during a demo
./scripts/psql.sh
\x on
SELECT pid, locktype, relation::regclass, mode, granted
  FROM pg_locks
  WHERE NOT granted OR relation IS NOT NULL
  ORDER BY pid;

# See active transactions and their isolation levels
SELECT pid, xact_start, state, query
  FROM pg_stat_activity
  WHERE state != 'idle';

# Confirm current isolation level inside a transaction
SHOW transaction_isolation;
```

## Adding a New Demo

1. Pick the next available number in `sql/` (e.g., `07_phantom_reads.sql`).
2. Start with a description and prerequisites comment block.
3. Reset state at the top using `\i /sql/reset.sql` (or document required state).
4. Mark sessions clearly, number steps in interleave order.
5. Include expected output and a final takeaway.
6. Update this file's "Repository Layout" section to reference the new file.
