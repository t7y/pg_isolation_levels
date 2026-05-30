# PostgreSQL Isolation Levels Lab

A hands-on sandbox for exploring PostgreSQL transaction isolation levels with two `psql` sessions side by side.

## Three ways to use this lab

- **Option A — Manual:** bring the environment up yourself and copy-paste from the `sql/` files. This README walks you through it.
- **Option B — Guided interactive walkthrough (in Cursor):** open this folder in Cursor and type `/start-setup`, then `/start-1` … `/start-6`. An AI instructor walks you through setup and each two-session demo step by step, waiting for you at each point. See [Guided walkthrough](#guided-walkthrough-in-cursor).
- **Option C — Reference website:** a browsable, searchable handbook of the same material lives in [`website/`](website/) (Nextra). See [Reference website](#reference-website-nextra).

> Tip: most common tasks are wrapped in the [`Makefile`](Makefile). Run `make help` to list them.

## Prerequisites

- Docker & Docker Compose

## Quick Start

```bash
cp .env.example .env
docker compose up -d
```

Wait for the healthcheck to pass, then open **two** terminal windows and start a `psql` session in each:

```bash
# Terminal 1
./scripts/psql.sh

# Terminal 2
./scripts/psql.sh
```

## Running the Demos

Each demo lives in a single SQL file under `sql/`. The files are meant to be read top-to-bottom — they contain `-- SESSION 1` and `-- SESSION 2` blocks numbered in execution order so you know which statement to run where.

### Initial setup

Run the schema + seed data once (only needed the first time):

```sql
\i /sql/00_setup.sql
```

### Reset between demos

Before starting each demo, reset all tables back to their initial state:

```bash
./scripts/reset.sh
```

Or from inside either `psql` session:

```sql
\i /sql/reset.sql
```

### Demo walkthrough

Work through the files in order. For each one, open it in your editor, then copy-paste the statements into the correct `psql` session following the step numbers.

| # | File | Isolation Level | What it shows |
|---|------|----------------|---------------|
| 1 | `sql/01_read_committed.sql` | Read Committed | Non-repeatable reads — the same `SELECT` returns different values within a single transaction because another transaction committed in between. |
| 2 | `sql/02_repeatable_read.sql` | Repeatable Read | Snapshot isolation gives a stable view, but writing a row that was concurrently modified triggers `SQLSTATE 40001` and forces a retry. |
| 3 | `sql/03_write_skew.sql` | Repeatable Read | Write skew — two transactions read overlapping data and write disjoint rows, violating a multi-row invariant (the "doctors on call" problem). RR can't catch this. |
| 4 | `sql/04_serializable.sql` | Serializable | SSI detects the read/write dependency cycle from demo 3 and aborts the second transaction with `40001`. The invariant is preserved. |
| 5 | `sql/05_for_update.sql` | Read Committed | `SELECT ... FOR UPDATE` as an escape hatch — pessimistic row locking serializes access without bumping up to Serializable. |
| 6 | `sql/06_balance_transfer.sql` | Read Committed | Lost update on a balance transfer — the read-compute-write pattern silently drops a transaction. Part B shows the `FOR UPDATE` fix. |

### Example: running demo 1

1. Reset state:

   ```sql
   -- either session
   \i /sql/reset.sql
   ```

2. **Session 1** — run STEP 1 (begin transaction, first `SELECT`):

   ```sql
   BEGIN ISOLATION LEVEL READ COMMITTED;
   SELECT value FROM counters WHERE name = 'widgets';
   -- you should see: 100
   ```

3. **Session 2** — run STEP 2 (update and commit):

   ```sql
   BEGIN ISOLATION LEVEL READ COMMITTED;
   UPDATE counters SET value = 200 WHERE name = 'widgets';
   COMMIT;
   ```

4. **Session 1** — run STEP 3 (second `SELECT` in the same transaction):

   ```sql
   SELECT value FROM counters WHERE name = 'widgets';
   -- you should see: 200  ← the value changed mid-transaction
   COMMIT;
   ```

Every other demo follows the same pattern: read the file, reset, paste each step into the right session.

## Guided walkthrough (in Cursor)

Prefer to be walked through it? Open this folder in [Cursor](https://cursor.com) and let the built-in AI instructor guide you. The interactive layer lives in `.cursor/` (an always-on instructor rule + slash commands) and `lessons/` (the teaching scripts).

1. Open the folder in Cursor.
2. In the chat/Composer pane, type `/start-setup` and press Enter. The instructor brings up Postgres and helps you open your two `psql` sessions.
3. Then run the demos in order:

| Command | Demo | What it shows |
|---|---|---|
| `/start-setup` | Setup | Docker up + two `psql` sessions + schema/seed |
| `/start-1` | Read Committed | Non-repeatable reads |
| `/start-2` | Repeatable Read | Snapshot isolation + `SQLSTATE 40001` on write conflict |
| `/start-3` | Write skew | Repeatable Read can't catch it |
| `/start-4` | Serializable | SSI catches the write-skew cycle |
| `/start-5` | `FOR UPDATE` | Pessimistic locking escape hatch |
| `/start-6` | Balance transfer | Stale-validation race + the `FOR UPDATE` fix |

You still run the SQL yourself in your two terminals (the instructor can't hold interactive sessions open) — it tells you exactly what to paste where, then waits for you to report what you saw.

## Reference website (Nextra)

A browsable, searchable handbook of the same demos lives in [`website/`](website/). It's a static [Nextra](https://nextra.site) site (Next.js + Pagefind full-text search) — the "look it up later" companion to the hands-on demos.

**Prerequisites:** Node.js 18+ and npm.

```bash
cd website
npm install      # first time only
npm run dev      # start the dev server
```

Then open **http://localhost:3000**.

To build the static site (output lands in `website/out/`, with the Pagefind search index generated automatically afterward):

```bash
cd website
npm run build
npm run preview  # serve the built site locally
```

Or use the Makefile targets from the repo root:

```bash
make site-install   # install dependencies
make site-dev       # dev server at http://localhost:3000
make site-build     # static build + search index
make site-preview   # serve the built site
```

## Make targets

Common tasks are wrapped in the [`Makefile`](Makefile):

```bash
make help        # list all targets

make up          # start PostgreSQL in Docker (creates .env if missing)
make psql        # open a psql session (run in two terminals)
make setup       # load schema + seed data (run once)
make reset       # reset all demo tables to their baseline
make logs        # follow PostgreSQL logs
make down        # stop and remove the container + volume

make site-install / site-dev / site-build / site-preview   # the Nextra website
```

## Useful Commands

```bash
# Watch SQL statements as they arrive at the server
docker compose logs -f postgres

# Inspect locks during a demo (from inside psql)
\x on
SELECT pid, locktype, relation::regclass, mode, granted
  FROM pg_locks
  WHERE NOT granted OR relation IS NOT NULL
  ORDER BY pid;

# See active transactions
SELECT pid, xact_start, state, query
  FROM pg_stat_activity
  WHERE state != 'idle';

# Check the current isolation level inside a transaction
SHOW transaction_isolation;
```

## Teardown

```bash
docker compose down -v
```
