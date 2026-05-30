# Demo 5: SELECT ... FOR UPDATE - The Pessimistic Locking Escape Hatch

**Teaching Script.** Follow `.cursor/SCRIPT_INSTRUCTIONS.md`. Source of truth for SQL: `sql/05_for_update.sql`. You guide; the learner runs everything in Session 1 / Session 2.

---

## What this demo proves

Sometimes you don't want to bump everything up to SERIALIZABLE and write retry loops. You just want: "I'm about to read this row, decide what to do, and write it back — nobody else touch it until I'm done." That's **`SELECT ... FOR UPDATE`**.

`FOR UPDATE` takes a **row-level lock** that blocks other writers AND other `FOR UPDATE` readers until the transaction commits or rolls back. Plain `SELECT`s are unaffected. We'll watch Session 2 **block** on the lock, then unblock and see the fresh value once Session 1 commits.

---

## Step 0: Reset

**Say:**

"Reset so `widgets` is 100:
```bash
./scripts/reset.sh
```
Keep both sessions open."

**STOP:** Confirm reset.
**USER:** Confirms.

---

## Step 1: Session 1 takes the lock

**Say:**

"In **Session 1**, paste:
```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
-- EXPECT: 100  (and the row is now locked for the rest of this txn)
SELECT value FROM counters WHERE name = 'widgets' FOR UPDATE;
```
Note we're at plain READ COMMITTED — no Serializable needed. That `FOR UPDATE` just locked the `widgets` row. Leave the transaction open."

**STOP:** Value?
**USER:** Reports `100`.

---

## Step 2: Session 2 tries the same lock — and BLOCKS

**Say:**

"Now **Session 2**, paste:
```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT value FROM counters WHERE name = 'widgets' FOR UPDATE;
```

Heads up: **`psql` will appear to hang** — it won't return a prompt. That's not a freeze; it's the lock wait. Session 2 is queued behind Session 1's lock on that row. Leave it sitting there and come back to Session 1."

**STOP:** Confirm Session 2 is hanging (no result, no prompt yet).
**USER:** Confirms it's blocked/waiting.

---

## Step 3: Session 1 does its work and commits

**Say:**

"Back in **Session 1**, do the read-modify-write and commit:
```sql
UPDATE counters SET value = value + 50 WHERE name = 'widgets';
-- EXPECT: 150
SELECT value FROM counters WHERE name = 'widgets';
COMMIT;
```
The moment Session 1 commits, it releases the lock — keep an eye on Session 2."

**STOP:** Did Session 1 show `150` and commit? And what happened in Session 2 the instant it committed?
**USER:** Reports Session 1 = `150` + `COMMIT`, and Session 2's hung query just returned.

---

## Step 4: Session 2 unblocks with the FRESH value

**Say:**

"Look at what **Session 2**'s `SELECT` returned when it unblocked:
```
-- EXPECT: 150  (NOT a stale 100)
```

This is the important part. Under READ COMMITTED, when a `FOR UPDATE` wait ends, Postgres **re-fetches the latest committed row**. So Session 2 sees `150`, the value Session 1 just wrote — not the `100` that was there when it first asked.

(Under REPEATABLE READ, this same situation would instead raise `SQLSTATE 40001` at this point, because the snapshot can't be reconciled. READ COMMITTED + FOR UPDATE gives you 'wait, then see the truth' with no retry.)

Now Session 2 can safely do its own update. In **Session 2**, paste:
```sql
UPDATE counters SET value = value - 30 WHERE name = 'widgets';
-- EXPECT: 120
SELECT value FROM counters WHERE name = 'widgets';
COMMIT;
```"

**STOP:** Did Session 2 see `150` on unblock, then land on `120` after its own update?
**USER:** Confirms `150` -> `120` -> `COMMIT`.

**Say:**

"Perfect: 100, then +50 = 150, then -30 = 120. Both updates applied in a clean, serialized order — no lost update, no retry, no `40001`."

---

## Wrap-up

**Say:**

"**Takeaway:** `FOR UPDATE` is a *pessimistic* lock — contending writers wait their turn instead of racing.

Pros:
- Simple to reason about, no retry loops
- Works at plain READ COMMITTED — no need for SERIALIZABLE

Cons:
- Serializes traffic on hot rows (throughput suffers)
- You can deadlock if sessions take locks in inconsistent order
- Long-held locks block everyone behind them

Rule of thumb: if you have a small number of clearly-defined 'source of truth' rows you're about to update, `FOR UPDATE` is often simpler and faster than SERIALIZABLE retries.

Last demo ties it all together on a money transfer — the bug *and* the fix. Type `/start-6`."

**STOP:** Answer questions, then point to `/start-6`.

---

## Notes for You

- Relay SQL verbatim from `sql/05_for_update.sql`.
- The two teaching beats: Step 2 (the *expected* hang — reassure them) and Step 4 (Session 2 unblocks seeing `150`, not stale `100`). 
- If Session 2 does NOT hang in Step 2, the likely cause is Session 1 didn't actually run `FOR UPDATE` or already committed. Have them re-check Session 1's transaction is open and used `FOR UPDATE`.
