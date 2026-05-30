# Demo 6: Balance Transfer - The Stale-Validation Race and Its Fix

**Teaching Script.** Follow `.cursor/SCRIPT_INSTRUCTIONS.md`. Source of truth for SQL: `sql/06_balance_transfer.sql`. This demo has **two parts** with a reset in between. You guide; the learner runs everything in Session 1 / Session 2.

---

## What this demo proves

Two sessions transfer money from Alice to Bob. Each reads Alice's balance, decides the transfer is affordable, and writes `SET balance = balance - N`. The *expression* is safe (Postgres re-evaluates it against the latest committed row), but the **decision to proceed was based on a stale read**.

- **Part A** — under READ COMMITTED with no locking, both validate against Alice's stale `$100`, both proceed, and the second transfer slams into the `CHECK (balance >= 0)` constraint with an ugly error.
- **Part B** — `SELECT ... FOR UPDATE` shifts the serialization point to the read, so the second session waits, sees the *true* balance, and rejects cleanly.

Starting state: Alice = `$100`, Bob = `$0`.

---

# PART A: The Race (no locking)

## Step 0: Reset

**Say:**

"Reset so Alice has \\$100 and Bob has \\$0:
```bash
./scripts/reset.sh
```
Keep both sessions open. Session 1 will transfer \\$60; Session 2 will transfer \\$50. Note that \\$60 + \\$50 = \\$110 > \\$100 — only one can legitimately succeed."

**STOP:** Confirm reset.
**USER:** Confirms.

---

## Step 1: Session 1 reads and validates

**Say:**

"In **Session 1**, paste:
```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
-- EXPECT: 100.00
SELECT balance FROM accounts WHERE id = 1;
```
App logic: 'Alice has 100, wants to send 60. 100 >= 60? Yes — proceed.' Leave the transaction open (don't write yet)."

**STOP:** Balance?
**USER:** Reports `100.00`.

---

## Step 2: Session 2 reads and validates (before Session 1 writes)

**Say:**

"In **Session 2**, paste:
```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
-- EXPECT: 100.00  (Session 1's writes are uncommitted / nonexistent yet)
SELECT balance FROM accounts WHERE id = 1;
```
App logic sees the **same** stale balance: '100 >= 50? Yes — proceed.' Both sessions now believe the transfer is affordable."

**STOP:** Balance?
**USER:** Reports `100.00`.

---

## Step 3: Session 1 executes the transfer and commits

**Say:**

"In **Session 1**, paste:
```sql
UPDATE accounts SET balance = balance - 60.00 WHERE id = 1;
UPDATE accounts SET balance = balance + 60.00 WHERE id = 2;
COMMIT;
-- EXPECT: Alice = 40.00, Bob = 60.00
SELECT * FROM accounts ORDER BY id;
```
Alice = 40, Bob = 60. So far, perfectly fine."

**STOP:** Confirm Alice = 40, Bob = 60, commit succeeded.
**USER:** Confirms.

---

## Step 4: Session 2 executes its transfer -> CHECK violation

**Say:**

"Now **Session 2** acts on its earlier (now stale) decision. It validated against \\$100, but Alice only has \\$40 now. Paste:
```sql
UPDATE accounts SET balance = balance - 50.00 WHERE id = 1;
```

What does Postgres say?"

**STOP:** What happened?
**USER:** Reports `ERROR: new row for relation "accounts" violates check constraint "accounts_balance_check"`.

**Say:**

"Postgres re-evaluated the expression against the live row: 40 - 50 = -10, which violates `CHECK (balance >= 0)`. The constraint saved us from corruption — but look at how the app experienced it: not as a clean 'insufficient funds' decision, but as a surprise database error at write time. And without that CHECK constraint, the balance would have silently gone negative. Roll back:
```sql
ROLLBACK;
```"

**STOP:** Confirm rollback.
**USER:** Confirms `ROLLBACK`.

---

## Step 5: Inspect Part A's outcome

**Say:**

"In **either** session, paste:
```sql
-- EXPECT: Alice = 40.00, Bob = 60.00
SELECT * FROM accounts ORDER BY id;
```
Session 1's transfer landed; Session 2 crashed into the constraint. No corruption — but the app validated against stale data and only found out via a database error. That's the bug. Now let's fix it."

**STOP:** Confirm Alice = 40, Bob = 60.
**USER:** Confirms.

---

# PART B: The Fix (SELECT ... FOR UPDATE)

## Step 6: Reset first

**Say:**

"We need a clean slate for the fixed version. Reset again:
```bash
./scripts/reset.sh
```
Back to Alice = \\$100, Bob = \\$0. Same two transfers (\\$60 and \\$50), same ordering — but this time we lock Alice's row on read."

**STOP:** Confirm reset.
**USER:** Confirms.

---

## Step 7: Session 1 locks Alice's row, then validates

**Say:**

"In **Session 1**, paste:
```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
-- EXPECT: 100.00  (row is now locked for the rest of this txn)
SELECT balance FROM accounts WHERE id = 1 FOR UPDATE;
```
App: '100 >= 60? Yes.' The difference from Part A: that `FOR UPDATE` locked Alice's row. Leave the transaction open."

**STOP:** Balance?
**USER:** Reports `100.00`.

---

## Step 8: Session 2 tries to lock the same row — and BLOCKS

**Say:**

"In **Session 2**, paste:
```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT balance FROM accounts WHERE id = 1 FOR UPDATE;
```

Just like demo 5, **`psql` will hang here** — Session 2 is waiting for Session 1's lock on Alice's row. It can't even read the balance yet, let alone decide. Leave it waiting and switch back to Session 1."

**STOP:** Confirm Session 2 is blocked/waiting.
**USER:** Confirms it's hanging.

---

## Step 9: Session 1 finishes the transfer and commits

**Say:**

"In **Session 1**, paste:
```sql
UPDATE accounts SET balance = balance - 60.00 WHERE id = 1;
UPDATE accounts SET balance = balance + 60.00 WHERE id = 2;
COMMIT;
```
The instant this commits, Session 2's blocked `SELECT` from Step 8 will unblock. Watch Session 2."

**STOP:** Did Session 1 commit, and did Session 2 wake up?
**USER:** Confirms Session 1 committed and Session 2's query returned.

---

## Step 10: Session 2 unblocks, sees the TRUE balance, rejects cleanly

**Say:**

"Look at what **Session 2**'s `SELECT` returned when it unblocked:
```
-- EXPECT: 40.00  (not 100!)
```

This is the fix in action. Because the lock made Session 2 *wait*, by the time it reads, Alice's real balance is \\$40. Now the app validates against the truth: '40 >= 50? **No** — reject.' No constraint error, no surprise. In **Session 2**, paste:
```sql
ROLLBACK;
```
The application cleanly declined the transfer because it saw the real balance *before* deciding."

**STOP:** Did Session 2 read `40.00` on unblock, then roll back?
**USER:** Confirms `40.00` then `ROLLBACK`.

---

## Step 11: Verify

**Say:**

"In **either** session, paste:
```sql
-- EXPECT: Alice = 40.00, Bob = 60.00
SELECT * FROM accounts ORDER BY id;
```
Same final numbers as Part A — but the *journey* was completely different. Session 1's transfer applied; Session 2 was rejected by the application logic, not by a database constraint error."

**STOP:** Confirm Alice = 40, Bob = 60.
**USER:** Confirms.

---

## Wrap-up

**Say:**

"**Takeaway:** Even with expression-based updates (`balance = balance - N`), the *validation logic* is still vulnerable under READ COMMITTED. In Part A, both transactions read \\$100, both decided 'affordable,' and the loser discovered the problem at write time via a CHECK error (or, without a CHECK, silent corruption).

`FOR UPDATE` shifts the serialization point to the `SELECT`: the second transaction blocks *before* it reads, and when it unblocks it sees the true committed value — so the application can make the right call. This is why production ledgers and payment systems almost always `SELECT ... FOR UPDATE` the account row: it turns a race condition into orderly, sequential access.

That's the whole lab! You've now seen:
- Read Committed -> non-repeatable reads (`/start-1`)
- Repeatable Read -> stable snapshot, but `40001` on write conflicts (`/start-2`)
- Write skew -> the anomaly RR can't catch (`/start-3`)
- Serializable -> SSI catches it, at the cost of retries (`/start-4`)
- `FOR UPDATE` -> pessimistic locking escape hatch (`/start-5`)
- Balance transfer -> the stale-validation race and its `FOR UPDATE` fix (this one)

Run `./scripts/reset.sh` any time you want to replay a demo. Nice work!"

**STOP:** Answer any final questions.

---

## Notes for You

- Relay SQL verbatim from `sql/06_balance_transfer.sql`.
- This is the longest demo — keep the STOP gates crisp and don't let Part A and Part B blur together. The reset in Step 6 is mandatory.
- Key beats: Step 4 (CHECK constraint error = the bug) and Step 10 (Session 2 unblocks to `40.00` and rejects cleanly = the fix). Make the contrast explicit.
- The `psql` hang in Step 8 is expected (lock wait), same as demo 5 — reassure the learner.
