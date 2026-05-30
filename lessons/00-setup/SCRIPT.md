# Setup: Environment & Two Sessions

**Teaching Script for the PostgreSQL Isolation Levels Lab**

Follow `.cursor/SCRIPT_INSTRUCTIONS.md`. This is the one lesson where you (the instructor) MAY run the one-shot helper commands yourself. You still must NOT open or drive `psql` — the learner keeps the two interactive sessions.

---

## Your Role

Get the learner from a fresh clone to a working lab: Postgres running in Docker, two `psql` sessions open side by side (Session 1 and Session 2), and the schema + seed data loaded. By the end they can run any of `/start-1` … `/start-6`.

## Learning Objectives

By the end of setup, the learner has:
1. A running `pg-isolation-lab` Postgres container
2. Two terminals, each in an interactive `psql` session (Session 1, Session 2)
3. The schema and seed data created via `00_setup.sql`
4. Verified the seed data and knows how to reset between demos

---

## Step 1: Welcome & prerequisites

**Say:**

"Welcome to the PostgreSQL Isolation Levels Lab! 

We're going to watch concurrency anomalies happen live — non-repeatable reads, write skew, lost updates — and see exactly which isolation levels and locking tricks prevent them.

The whole lab runs on **two `psql` sessions side by side**. I'll tell you which statement to paste into which session, then wait for you to tell me what you saw. I drive the narration; you drive the keyboard.

First, the only prerequisite: **Docker** (with Docker Compose). 

Do you have Docker installed and running?"

**STOP:** Wait for the learner to confirm Docker is available.
**USER:** Confirms Docker is running (or needs to install/start it — point them to Docker Desktop if so).

---

## Step 2: Start Postgres

**Say:**

"Great. Let me bring up the database. This copies the example env file and starts the container in the background."

**ACTION:** Run these one-shot helpers yourself (from the repo root):
```bash
cp -n .env.example .env
docker compose up -d
```

Then confirm health:

**ACTION:** Run `docker compose ps` and check the `postgres` service is `running`/`healthy`. If it isn't healthy yet, wait a couple seconds and check again (the healthcheck runs every 2s).

**Say (once healthy):**

"Postgres is up and healthy — the container is called `pg-isolation-lab`, listening on port 5432. 

The container mounts the `sql/` folder read-only at `/sql`, so inside `psql` you can load any demo file with `\i /sql/...`."

**STOP:** Confirm the learner sees the container running.
**USER:** Confirms.

---

## Step 3: Open two psql sessions

**Say:**

"Now the important part: open **two** terminal windows (or two tabs/splits). We'll call them Session 1 and Session 2, and they stay open for the whole lab.

In **each** terminal, from the repo root, run:
```bash
./scripts/psql.sh
```

That drops you into an interactive `psql` prompt connected to the lab database. You'll know it worked when you see a prompt like `isolation_lab=#`.

- **Terminal 1 -> this is Session 1**
- **Terminal 2 -> this is Session 2**

Open both now."

**STOP:** Wait until the learner confirms both terminals show the `isolation_lab=#` prompt.
**USER:** Confirms two open psql sessions. (If `psql.sh` errors, check the container is healthy and they're running from the repo root.)

---

## Step 4: Create the schema and seed data

**Say:**

"Let's create the tables and seed data. This only needs to happen once. In **Session 1**, paste:
```sql
\i /sql/00_setup.sql
```

This creates three tables — `counters`, `doctors`, and `accounts` — and seeds them. It's idempotent, so it's safe even if you run it again."

**STOP:** Ask the learner to confirm it ran without errors.
**USER:** Reports `CREATE TABLE` / `INSERT` output with no errors.

---

## Step 5: Verify the seed data

**Say:**

"Quick sanity check. Still in **Session 1**, paste:
```sql
SELECT * FROM counters ORDER BY name;
SELECT * FROM doctors ORDER BY id;
SELECT * FROM accounts ORDER BY id;
```

You should see:
- `counters`: `hits = 0`, `widgets = 100`
- `doctors`: Alice and Bob, both `on_call = true`
- `accounts`: Alice = `100.00`, Bob = `0.00`

These three tables back all six demos."

**STOP:** Confirm the values match.
**USER:** Confirms the seed values.

---

## Step 6: How to reset, and what's next

**Say:**

"One more thing — the reset. Each demo should start from this clean baseline. Between demos, run this from a **third** terminal (or any non-psql shell) at the repo root:
```bash
./scripts/reset.sh
```

Or, from inside either `psql` session:
```sql
\i /sql/reset.sql
```

That truncates and reseeds all three tables. Each demo lesson will remind you to reset first.

You're all set! Here's the roadmap:

| Command | Demo | What it shows |
|---|---|---|
| `/start-1` | Read Committed | Non-repeatable reads |
| `/start-2` | Repeatable Read | Snapshot isolation + `40001` on write conflict |
| `/start-3` | Write skew | Repeatable Read can't catch it |
| `/start-4` | Serializable | SSI catches the write-skew cycle |
| `/start-5` | `FOR UPDATE` | Pessimistic locking escape hatch |
| `/start-6` | Balance transfer | Stale-validation race + the `FOR UPDATE` fix |

When you're ready, type `/start-1` to see your first anomaly. Keep both sessions open!"

**STOP:** Answer any questions; otherwise wrap up.

---

## Notes for You (the instructor)

- You MAY run `cp`, `docker compose up -d`, `docker compose ps`, `docker compose logs postgres`, `./scripts/reset.sh`. You must NOT run anything inside `psql`.
- If `docker compose up -d` fails because port 5432 is taken, tell the learner to set `POSTGRES_PORT` in `.env` to a free port and re-run.
- If the learner is on a system without the `docker compose` plugin, suggest `docker-compose` (hyphenated) as a fallback.
- Don't rush the STOP gates — a clean two-session setup is what makes every later demo work.
