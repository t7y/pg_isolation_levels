# Demo 4: Serializable - SSI Catches the Write-Skew Cycle

**Teaching Script.** Follow `.cursor/SCRIPT_INSTRUCTIONS.md`. Source of truth for SQL: `sql/04_serializable.sql`. You guide; the learner runs everything in Session 1 / Session 2.

---

## What this demo proves

The fix for write skew: **SERIALIZABLE** isolation. Postgres implements it via **Serializable Snapshot Isolation (SSI)**. Like Repeatable Read, each transaction sees a snapshot — but SSI also tracks **predicate reads** (which rows your `WHERE` clauses depended on). If at commit time it spots a read/write dependency pattern that couldn't have occurred in any serial order, it aborts one transaction with **SQLSTATE 40001**.

We replay the exact doctors-on-call scenario from demo 3. The first commit succeeds; the second hits a serialization failure and must retry. The invariant is preserved.

---

## Step 0: Reset

**Say:**

"Reset so both doctors are on call again:
```bash
./scripts/reset.sh
```
Keep both sessions open. Session 1 = Alice, Session 2 = Bob, same as last demo."

**STOP:** Confirm reset.
**USER:** Confirms.

---

## Step 1: Session 1 opens SERIALIZABLE and reads

**Say:**

"This time we use `SERIALIZABLE`. In **Session 1**, paste:
```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;
-- EXPECT: 2
SELECT count(*) FROM doctors WHERE on_call;
```"

**STOP:** Count?
**USER:** Reports `2`.

---

## Step 2: Session 2 opens SERIALIZABLE and reads

**Say:**

"In **Session 2**, paste:
```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;
-- EXPECT: 2
SELECT count(*) FROM doctors WHERE on_call;
```
Both transactions are open, both saw 2 on call — identical to demo 3 so far."

**STOP:** Count?
**USER:** Reports `2`.

---

## Step 3: Session 1 (Alice) goes off call and commits

**Say:**

"In **Session 1**, paste:
```sql
-- EXPECT: 1
SELECT count(*) FROM doctors WHERE on_call AND id <> 1;
UPDATE doctors SET on_call = false WHERE id = 1;
COMMIT;
```
Alice's commit should succeed — first writer wins."

**STOP:** Did Session 1 commit cleanly?
**USER:** Confirms `1` then `COMMIT` succeeds.

---

## Step 4: Session 2 (Bob) tries the same -> 40001

**Say:**

"Now **Session 2**, Bob runs the mirror image. In demo 3 this commit *succeeded* and broke the invariant. Watch what Serializable does. Paste:
```sql
-- EXPECT: 1  (still operating on the snapshot)
SELECT count(*) FROM doctors WHERE on_call AND id <> 2;
UPDATE doctors SET on_call = false WHERE id = 2;
COMMIT;
```

What happens — on the `UPDATE` or on the `COMMIT`?"

**STOP:** What did Postgres report?
**USER:** Reports `ERROR: could not serialize access due to read/write dependencies among transactions`, `SQLSTATE 40001`, with a hint to retry. (It may fire on the UPDATE or on the COMMIT.)

**Say:**

"There it is. SSI noticed that Bob *read* the set of on-call doctors that Alice then *modified*, and vice versa — a dependency cycle that has no equivalent serial ordering. Rather than let Bob commit and zero out the on-call count, Postgres aborted his transaction. The hint even says: 'The transaction might succeed if retried.'"

---

## Step 5: Retry — now Bob sees reality

**Say:**

"Same rule as demo 2: on `40001`, retry the whole transaction. In **Session 2**, paste:
```sql
ROLLBACK;  -- safe even if already aborted

BEGIN ISOLATION LEVEL SERIALIZABLE;
-- EXPECT: 1  (Alice already off call)
SELECT count(*) FROM doctors WHERE on_call;
COMMIT;
```

Now Bob's fresh snapshot shows only **1** doctor on call. His application logic should look at that and decide **not** to go off call — leaving the hospital covered. We just commit without changing anything."

**STOP:** Did the retry show `1` and commit cleanly?
**USER:** Confirms `1` then `COMMIT`.

---

## Step 6: Verify the invariant held

**Say:**

"Final check. In **either** session, paste:
```sql
-- EXPECT: 1  <- Bob is still on call. Invariant preserved.
SELECT count(*) AS doctors_on_call FROM doctors WHERE on_call;
```"

**STOP:** Count?
**USER:** Reports `1`.

**Say:**

"One doctor on call — exactly what we needed. Compare to demo 3, where the same sequence left us with zero."

---

## Wrap-up

**Say:**

"**Takeaway:** SERIALIZABLE makes your application logic correct *as if* every transaction ran one at a time — with no extra locks in your code. The price: your code MUST handle `SQLSTATE 40001` by retrying the whole transaction. 

It's opt-in per transaction (`BEGIN ISOLATION LEVEL SERIALIZABLE`), so many apps use it only for the handful of paths with non-trivial invariants, and leave everything else at Read Committed.

But retries aren't the only tool. Sometimes a plain lock is simpler. Type `/start-5` to meet `SELECT ... FOR UPDATE`."

**STOP:** Answer questions, then point to `/start-5`.

---

## Notes for You

- Relay SQL verbatim from `sql/04_serializable.sql`.
- Set expectations in Step 4: the `40001` may appear on the `UPDATE` or the `COMMIT` depending on SSI's tracker — both are correct. Don't tell the learner it'll definitely be one or the other.
- Contrast with demo 3 explicitly (Step 6): same moves, opposite outcome.
