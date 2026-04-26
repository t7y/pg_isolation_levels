-- 04_serializable.sql
--
-- The fix for write skew: SERIALIZABLE isolation.
--
-- PostgreSQL implements SERIALIZABLE via Serializable Snapshot Isolation
-- (SSI). Like REPEATABLE READ, each transaction sees a snapshot. But
-- SSI also tracks "predicate" reads -- which rows your queries' WHERE
-- clauses depended on. If at commit time it detects a pattern of
-- read/write dependencies that could not have happened in any serial
-- order, it aborts one of the transactions with SQLSTATE 40001.
--
-- We replay the doctors-on-call write skew from 03 under SERIALIZABLE.
-- The first commit succeeds; the second commit hits a serialization
-- failure and must retry.
--
-- Prerequisite: run /sql/reset.sql.


-- =====================================================================
-- SESSION 1 -- STEP 1
-- =====================================================================
BEGIN ISOLATION LEVEL SERIALIZABLE;

-- EXPECT: 2
SELECT count(*) FROM doctors WHERE on_call;


-- =====================================================================
-- SESSION 2 -- STEP 2
-- =====================================================================
BEGIN ISOLATION LEVEL SERIALIZABLE;

-- EXPECT: 2
SELECT count(*) FROM doctors WHERE on_call;


-- =====================================================================
-- SESSION 1 -- STEP 3: Alice goes off call.
-- =====================================================================
-- EXPECT: 1
SELECT count(*) FROM doctors WHERE on_call AND id <> 1;

UPDATE doctors SET on_call = false WHERE id = 1;

-- EXPECT: COMMIT succeeds (first writer wins).
COMMIT;


-- =====================================================================
-- SESSION 2 -- STEP 4: Bob tries to go off call.
-- =====================================================================
-- EXPECT: 1  (still operating on the snapshot)
SELECT count(*) FROM doctors WHERE on_call AND id <> 2;

UPDATE doctors SET on_call = false WHERE id = 2;

-- EXPECT: ERROR  could not serialize access due to read/write
--         dependencies among transactions
--         SQLSTATE 40001
--         Hint: The transaction might succeed if retried.
--
-- Note: the failure may show up on the UPDATE above OR on the COMMIT
-- below, depending on what SSI's dependency tracker decides. Either
-- way, this transaction must roll back and retry.
COMMIT;


-- =====================================================================
-- SESSION 2 -- STEP 5: retry. Now the snapshot reflects reality.
-- =====================================================================
ROLLBACK;  -- safe even if already aborted

BEGIN ISOLATION LEVEL SERIALIZABLE;

-- EXPECT: 1  (Alice already off call)
SELECT count(*) FROM doctors WHERE on_call;

-- The application logic should now decide NOT to take Bob off call,
-- because that would leave zero doctors on call. The retry sees the
-- truth and the invariant is preserved.

COMMIT;


-- =====================================================================
-- AFTER
-- =====================================================================
-- EXPECT: 1  -- Bob is still on call. Invariant preserved.
SELECT count(*) AS doctors_on_call FROM doctors WHERE on_call;


-- TAKEAWAY:
--   SERIALIZABLE makes your application logic correct *as if* every
--   transaction ran one at a time, with no extra locks in your code.
--   The price is that your code MUST handle SQLSTATE 40001 by retrying
--   the whole transaction. SSI is opt-in per transaction; you don't
--   have to make it the global default. Many apps use it just for the
--   handful of paths that have non-trivial invariants.
