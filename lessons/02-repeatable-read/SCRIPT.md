# Demo 2: Repeatable Read - Stable Snapshot & SQLSTATE 40001

**Teaching Script.** Follow `.cursor/SCRIPT_INSTRUCTIONS.md`. Source of truth for SQL: `sql/02_repeatable_read.sql`. You guide; the learner runs everything in Session 1 / Session 2.

---

## What this demo proves

Two lessons in one:

(a) **REPEATABLE READ** gives every statement in a transaction the **same snapshot**, taken at the first statement. Concurrent commits are invisible — no more non-repeatable reads.

(b) But if you then `UPDATE` a row that a concurrent transaction already committed a change to, Postgres refuses with `ERROR: could not serialize access due to concurrent update` (**SQLSTATE 40001**). The transaction is dead; you must roll back and retry.

---

## Step 0: Reset

**Say:**

"Reset to baseline so `widgets` is 100 again:
```bash
./scripts/reset.sh
```
Keep both sessions open."

**STOP:** Confirm reset.
**USER:** Confirms.

---

## Step 1: Session 1 opens REPEATABLE READ and reads

**Say:**

"In **Session 1**, paste:
```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- EXPECT: 100
SELECT value FROM counters WHERE name = 'widgets';
```
That first `SELECT` fixes Session 1's snapshot. Leave the transaction open."

**STOP:** What value?
**USER:** Reports `100`.

---

## Step 2: Session 2 updates and commits

**Say:**

"In **Session 2**, paste:
```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
UPDATE counters SET value = 200 WHERE name = 'widgets';
COMMIT;
```
Session 2 has committed `widgets = 200`."

**STOP:** Confirm the commit.
**USER:** Confirms `COMMIT`.

---

## Step 3: Session 1 re-reads — snapshot holds

**Say:**

"Back to **Session 1** (still in the same open transaction). Paste:
```sql
-- EXPECT: 100  <- snapshot isolation: still the value as of Step 1
SELECT value FROM counters WHERE name = 'widgets';
```

This is the opposite of demo 1! What do you see?"

**STOP:** What value?
**USER:** Reports `100` (NOT 200).

**Say:**

"That's snapshot isolation. Session 2's commit is invisible to Session 1's transaction. Compare that to demo 1, where the value flipped to 200. So far, Repeatable Read looks strictly better... watch what happens when we try to *write*."

---

## Step 4: Session 1 tries to UPDATE -> 40001

**Say:**

"Still in **Session 1**, paste:
```sql
UPDATE counters SET value = value + 1 WHERE name = 'widgets';
```

What does Postgres say?"

**STOP:** What happened?
**USER:** Reports `ERROR: could not serialize access due to concurrent update` / `SQLSTATE 40001`.

**Say:**

"That `40001` is the headline of this demo — and it's a *good* error. Session 1's snapshot says `widgets = 100`, but the committed row is now `200`. Postgres can't safely apply `value = value + 1` on top of a stale snapshot, so it aborts the transaction rather than silently doing the wrong thing. 

The transaction is now poisoned — the only legal move is to roll back. Paste:
```sql
ROLLBACK;
```"

**STOP:** Confirm rollback.
**USER:** Confirms `ROLLBACK`.

---

## Step 5: Retry — now it sees fresh data

**Say:**

"The correct response to `40001` is always: **retry the whole transaction from the top**. In **Session 1**, paste:
```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- EXPECT: 200
SELECT value FROM counters WHERE name = 'widgets';
UPDATE counters SET value = value + 1 WHERE name = 'widgets';
-- EXPECT: 201
SELECT value FROM counters WHERE name = 'widgets';
COMMIT;
```

The retry takes a fresh snapshot (now `200`), applies the increment, and commits `201`."

**STOP:** Did you get `200` then `201`, and a clean commit?
**USER:** Confirms `200` -> `201` -> `COMMIT`.

---

## Wrap-up

**Say:**

"**Takeaway:** REPEATABLE READ is great for read-mostly logic that needs a consistent view. But the moment you mix in writes, your application **must** be ready to catch `SQLSTATE 40001` and retry the whole transaction. There's no fixing it up in place — the snapshot is dead the instant `40001` fires.

Next up: a sneakier anomaly that Repeatable Read *can't* catch at all. Type `/start-3`."

**STOP:** Answer questions, then point to `/start-3`.

---

## Notes for You

- Relay SQL verbatim from `sql/02_repeatable_read.sql`.
- The two big beats: Step 3 (`100`, snapshot holds — contrast with demo 1) and Step 4 (`40001` on the write). Make both land.
- Reassure: `40001` is expected and correct, not a setup mistake.
