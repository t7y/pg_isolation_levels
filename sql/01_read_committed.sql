-- 01_read_committed.sql
--
-- Anomaly: NON-REPEATABLE READ.
--
-- Under READ COMMITTED (PostgreSQL's default), each statement within a
-- transaction sees its own fresh snapshot. So if another transaction
-- commits a change between two SELECTs, the second SELECT sees the new
-- value. The same query inside the same transaction returns different
-- rows -- a "non-repeatable read".
--
-- Expected outcome: Session 1 sees value=100, then 200, within the same
-- transaction.
--
-- Prerequisite: run /sql/reset.sql before starting (or \i /sql/reset.sql
-- in either session).


-- =====================================================================
-- SESSION 1 -- STEP 1: open a READ COMMITTED transaction and read.
-- =====================================================================
BEGIN ISOLATION LEVEL READ COMMITTED;

-- EXPECT: 100
SELECT value FROM counters WHERE name = 'widgets';


-- =====================================================================
-- SESSION 2 -- STEP 2: in a separate psql session, update and commit.
-- =====================================================================
BEGIN ISOLATION LEVEL READ COMMITTED;
UPDATE counters SET value = 200 WHERE name = 'widgets';
COMMIT;


-- =====================================================================
-- SESSION 1 -- STEP 3: re-read in the *same* still-open transaction.
-- =====================================================================
-- EXPECT: 200  -- the value changed mid-transaction!
SELECT value FROM counters WHERE name = 'widgets';

COMMIT;


-- TAKEAWAY:
--   Under READ COMMITTED, "value" is not stable within a transaction.
--   Every statement sees the latest committed data. If your business
--   logic reads, computes, then writes, an interleaved commit can change
--   what you read out from underneath you. Use REPEATABLE READ if you
--   need a stable snapshot, or SELECT ... FOR UPDATE to lock specific
--   rows (see 05_for_update.sql).
