-- 06_balance_transfer.sql
--
-- Anomaly: STALE VALIDATION on a balance transfer.
--
-- Two concurrent sessions transfer money from Alice to Bob. Each reads
-- Alice's balance, decides the transfer is affordable, and writes with
-- `SET balance = balance - N`. The expression itself is safe — Postgres
-- re-evaluates it against the latest committed row. But the decision
-- to proceed was based on a stale read. When both transfers together
-- exceed the available balance, the second transaction hits the CHECK
-- constraint with an unexpected error instead of being cleanly rejected.
--
-- Part A demonstrates the bug.
-- Part B shows the fix with SELECT ... FOR UPDATE.
--
-- Starting state: Alice has $100, Bob has $0.
--
-- Prerequisite: run /sql/reset.sql.


-- =====================================================================
-- PART A: THE RACE (Read Committed, no locking)
-- =====================================================================
--
-- Session 1 transfers $60 from Alice to Bob.
-- Session 2 transfers $50 from Alice to Bob.
-- Only one can succeed ($60 + $50 = $110 > $100), but both sessions
-- validate against the stale balance of $100 and proceed.


-- =====================================================================
-- SESSION 1 -- STEP 1: read balances and validate.
-- =====================================================================
BEGIN ISOLATION LEVEL READ COMMITTED;

-- EXPECT: 100.00
SELECT balance FROM accounts WHERE id = 1;

-- Application logic: Alice has 100, wants to send 60.
-- 100 >= 60? Yes. Proceed with transfer.


-- =====================================================================
-- SESSION 2 -- STEP 2: read balances and validate (before Session 1 commits).
-- =====================================================================
BEGIN ISOLATION LEVEL READ COMMITTED;

-- EXPECT: 100.00  (Session 1's writes are uncommitted, invisible)
SELECT balance FROM accounts WHERE id = 1;

-- Application logic sees the SAME stale balance:
-- 100 >= 50? Yes. Proceed with transfer.


-- =====================================================================
-- SESSION 1 -- STEP 3: execute the transfer and commit.
-- =====================================================================
UPDATE accounts SET balance = balance - 60.00 WHERE id = 1;
UPDATE accounts SET balance = balance + 60.00 WHERE id = 2;
COMMIT;

-- Alice = 40, Bob = 60.  So far so good.
SELECT * FROM accounts ORDER BY id;


-- =====================================================================
-- SESSION 2 -- STEP 4: execute its transfer.
-- =====================================================================
-- Session 2's validation said "100 >= 50, go ahead" — but Alice now
-- has 40. Postgres re-evaluates the expression: 40 - 50 = -10.
--
-- EXPECT: ERROR  new row for relation "accounts" violates check
--         constraint "accounts_balance_check"
--
-- The CHECK constraint saved us from corruption, but the app gets an
-- ugly constraint error instead of a clean "insufficient funds" response.
-- Without the CHECK, the balance would silently go negative.
UPDATE accounts SET balance = balance - 50.00 WHERE id = 1;

ROLLBACK;


-- =====================================================================
-- EITHER SESSION -- check the state.
-- =====================================================================
-- EXPECT: Alice = 40.00, Bob = 60.00
--
--   Session 1's transfer landed. Session 2 crashed with a constraint
--   error. No data corruption, but the app had no chance to handle
--   this gracefully — it validated against stale data and only found
--   out at UPDATE time via a database error.
SELECT * FROM accounts ORDER BY id;



-- =====================================================================
-- PART B: THE FIX (Read Committed + SELECT ... FOR UPDATE)
-- =====================================================================
--
-- Reset first!
--   \i /sql/reset.sql
--
-- Same two transfers ($60 and $50), same ordering, but FOR UPDATE
-- forces Session 2 to wait and re-read the true balance BEFORE
-- validating.


-- =====================================================================
-- SESSION 1 -- STEP 5: lock Alice's row, then validate.
-- =====================================================================
BEGIN ISOLATION LEVEL READ COMMITTED;

-- EXPECT: 100.00  (row is now locked for the rest of this transaction)
SELECT balance FROM accounts WHERE id = 1 FOR UPDATE;

-- App: 100 >= 60? Yes.


-- =====================================================================
-- SESSION 2 -- STEP 6: try to lock the same row. This BLOCKS.
-- =====================================================================
BEGIN ISOLATION LEVEL READ COMMITTED;

-- EXPECT: psql hangs — waiting for Session 1's lock on Alice's row.
SELECT balance FROM accounts WHERE id = 1 FOR UPDATE;


-- =====================================================================
-- SESSION 1 -- STEP 7: finish the transfer and commit.
-- =====================================================================
UPDATE accounts SET balance = balance - 60.00 WHERE id = 1;
UPDATE accounts SET balance = balance + 60.00 WHERE id = 2;
COMMIT;

-- Session 2's SELECT in Step 6 unblocks NOW.


-- =====================================================================
-- SESSION 2 -- STEP 8: unblocked — reads the REAL balance.
-- =====================================================================
-- The SELECT from Step 6 returns with the post-commit value:
-- EXPECT: 40.00  (not 100!)
--
-- Session 2 now sees the truth BEFORE deciding whether to proceed.
-- App: 40 >= 50? No. Reject the transfer cleanly.

ROLLBACK;


-- =====================================================================
-- EITHER SESSION -- verify.
-- =====================================================================
-- EXPECT: Alice = 40.00, Bob = 60.00
--
--   Session 1's transfer applied. Session 2 was cleanly rejected by
--   the application — no constraint error, no surprise. The app saw
--   the real balance and made the right call.
SELECT * FROM accounts ORDER BY id;


-- TAKEAWAY:
--   Even with expression-based UPDATEs (`balance = balance - N`), the
--   validation logic is still vulnerable under READ COMMITTED. Both
--   transactions read Alice's balance as 100 and decide "this transfer
--   is affordable" — but only one of them can be right. Without
--   locking, the second transaction discovers the problem at UPDATE
--   time via a CHECK constraint error (or worse, no error at all if
--   there's no CHECK).
--
--   FOR UPDATE shifts the serialization point to the SELECT: the
--   second transaction blocks before it even reads the balance. When
--   it unblocks it sees the true committed value and the application
--   can make the right decision — reject cleanly or proceed safely.
--
--   This is why production ledgers and payment systems almost always
--   use SELECT ... FOR UPDATE on the account row: it turns a race
--   condition into orderly, sequential access.
