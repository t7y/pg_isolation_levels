-- 02_repeatable_read.sql
--
-- Two things to learn here:
--
--   (a) REPEATABLE READ gives every statement in a transaction the SAME
--       snapshot, taken at the first statement. Concurrent commits are
--       invisible to it. No more non-repeatable reads.
--
--   (b) But if you then try to UPDATE a row that *was* modified by a
--       concurrent committed transaction, PostgreSQL refuses with:
--
--           ERROR:  could not serialize access due to concurrent update
--           SQLSTATE: 40001
--
--       This is the engine telling you: "I can't safely apply your write
--       on top of an outdated snapshot. Retry the whole transaction."
--
-- Prerequisite: run /sql/reset.sql.


-- =====================================================================
-- SESSION 1 -- STEP 1: open RR and take a snapshot by reading.
-- =====================================================================
BEGIN ISOLATION LEVEL REPEATABLE READ;

-- EXPECT: 100
SELECT value FROM counters WHERE name = 'widgets';


-- =====================================================================
-- SESSION 2 -- STEP 2: update and commit in a separate transaction.
-- =====================================================================
BEGIN ISOLATION LEVEL READ COMMITTED;
UPDATE counters SET value = 200 WHERE name = 'widgets';
COMMIT;


-- =====================================================================
-- SESSION 1 -- STEP 3: re-read in the still-open RR transaction.
-- =====================================================================
-- EXPECT: 100  -- snapshot isolation: still the value as of STEP 1.
SELECT value FROM counters WHERE name = 'widgets';


-- =====================================================================
-- SESSION 1 -- STEP 4: try to UPDATE the same row.
-- =====================================================================
-- EXPECT: ERROR  could not serialize access due to concurrent update
--         SQLSTATE 40001
--
-- The transaction is now aborted; the only legal next statement is
-- ROLLBACK (or COMMIT, which behaves like ROLLBACK once aborted).
UPDATE counters SET value = value + 1 WHERE name = 'widgets';

ROLLBACK;


-- =====================================================================
-- SESSION 1 -- STEP 5: retry the transaction; it now sees fresh data.
-- =====================================================================
BEGIN ISOLATION LEVEL REPEATABLE READ;

-- EXPECT: 200
SELECT value FROM counters WHERE name = 'widgets';

UPDATE counters SET value = value + 1 WHERE name = 'widgets';

-- EXPECT: 201
SELECT value FROM counters WHERE name = 'widgets';

COMMIT;


-- TAKEAWAY:
--   REPEATABLE READ is your friend for read-mostly logic that needs a
--   consistent view of the world. But once you mix in writes, your
--   application MUST be prepared to catch SQLSTATE 40001 and retry the
--   whole transaction from the top. There is no way to "fix it up" in
--   place -- the snapshot is dead the moment 40001 fires.
