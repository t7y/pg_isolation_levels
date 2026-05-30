# Demo 1: Read Committed - Non-Repeatable Reads

**Teaching Script.** Follow `.cursor/SCRIPT_INSTRUCTIONS.md`. Source of truth for SQL: `sql/01_read_committed.sql`. You guide; the learner runs everything in Session 1 / Session 2.

---

## What this demo proves

Under **READ COMMITTED** (Postgres's default), each *statement* gets its own fresh snapshot. So a value you read at the start of a transaction can change underneath you if another transaction commits in between. The same `SELECT` returns different rows within one transaction — a **non-repeatable read**.

Expected arc: Session 1 reads `100`, Session 2 commits `200`, Session 1 re-reads and now sees `200` — all inside Session 1's single open transaction.

---

## Step 0: Reset

**Say:**

"Let's start clean. Run the reset so `widgets` is back to 100. From a non-psql shell at the repo root:
```bash
./scripts/reset.sh
```
(or `\i /sql/reset.sql` in either session). Keep both psql sessions open."

**STOP:** Confirm reset completed.
**USER:** Confirms.

---

## Step 1: Session 1 opens a transaction and reads

**Say:**

"In **Session 1**, paste this to open a Read Committed transaction and read the counter:
```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT value FROM counters WHERE name = 'widgets';
```
You should get back `100`. Leave this transaction **open** — don't commit yet."

**STOP:** What value did Session 1 return?
**USER:** Reports `100`.

---

## Step 2: Session 2 updates and commits

**Say:**

"Now switch to **Session 2**. While Session 1's transaction is still open, paste:
```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
UPDATE counters SET value = 200 WHERE name = 'widgets';
COMMIT;
```
Session 2 just changed `widgets` to 200 and committed."

**STOP:** Did Session 2 commit cleanly?
**USER:** Confirms `COMMIT`.

---

## Step 3: Session 1 re-reads in the SAME transaction

**Say:**

"Back to **Session 1** — the transaction you opened in Step 1 is still going. Paste:
```sql
-- EXPECT: 200  <- the value changed mid-transaction!
SELECT value FROM counters WHERE name = 'widgets';
COMMIT;
```

What do you see?"

**STOP:** What value came back this time?
**USER:** Reports `200`.

**Say (after they confirm):**

"That's the anomaly. The *exact same query* in the *same transaction* returned `100` and then `200`. Under Read Committed, every statement sees the latest committed data — your transaction has no stable view of the world."

---

## Wrap-up

**Say:**

"**Takeaway:** Under READ COMMITTED, a value is not stable within a transaction. If your business logic does read -> compute -> write, an interleaved commit can change what you read out from under you. 

Two ways to get a stable view:
- **REPEATABLE READ** — a single snapshot for the whole transaction (that's `/start-2`)
- **`SELECT ... FOR UPDATE`** — lock the specific rows you care about (that's `/start-5`)

Ready for the next one? Type `/start-2` to see how Repeatable Read fixes this — and the new problem it introduces."

**STOP:** Answer questions, then point to `/start-2`.

---

## Notes for You

- Relay SQL verbatim from `sql/01_read_committed.sql`.
- The key teaching beat is the contrast between Step 1 (`100`) and Step 3 (`200`) in one transaction. Make sure the learner notices it's the same query.
- If Session 1 shows `100` again in Step 3, the most likely cause is Session 2 didn't actually commit, or they reset after Step 1. Have them re-check Session 2.
