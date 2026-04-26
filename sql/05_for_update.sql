-- 05_for_update.sql
--
-- The "escape hatch": pessimistic row locking under READ COMMITTED.
--
-- Sometimes you don't want to bump everything up to SERIALIZABLE. You
-- just want to say "I'm about to read this row, decide what to do, and
-- write it back -- nobody else touch it until I'm done." That's what
-- SELECT ... FOR UPDATE is for.
--
-- FOR UPDATE acquires a row-level lock that blocks other writers AND
-- other FOR UPDATE readers, until the transaction commits or rolls
-- back. Plain SELECTs are unaffected -- they continue to see the last
-- committed version.
--
-- We'll demonstrate it on the `widgets` counter: Session 1 takes the
-- lock, Session 2 tries to take it and waits. Once Session 1 commits,
-- Session 2 unblocks and sees the new value.
--
-- Prerequisite: run /sql/reset.sql.  (widgets starts at 100)


-- =====================================================================
-- SESSION 1 -- STEP 1: take a row-level lock.
-- =====================================================================
BEGIN ISOLATION LEVEL READ COMMITTED;

-- EXPECT: 100  (and the row is now locked for the rest of this txn)
SELECT value FROM counters WHERE name = 'widgets' FOR UPDATE;


-- =====================================================================
-- SESSION 2 -- STEP 2: try to take the same lock. This BLOCKS.
-- =====================================================================
BEGIN ISOLATION LEVEL READ COMMITTED;

-- EXPECT: psql appears to hang. That's the lock wait. It will
--         unblock as soon as Session 1 commits or rolls back.
SELECT value FROM counters WHERE name = 'widgets' FOR UPDATE;


-- =====================================================================
-- SESSION 1 -- STEP 3: do the read-modify-write and commit.
-- =====================================================================
UPDATE counters SET value = value + 50 WHERE name = 'widgets';

-- EXPECT: 150
SELECT value FROM counters WHERE name = 'widgets';

COMMIT;


-- =====================================================================
-- SESSION 2 -- STEP 4: the previous SELECT now returns immediately.
-- =====================================================================
-- EXPECT: 150  -- Session 2 sees the value Session 1 just committed,
--                NOT a stale 100. FOR UPDATE always re-fetches the
--                latest committed row when it unblocks under
--                READ COMMITTED. (Under REPEATABLE READ this would
--                instead raise SQLSTATE 40001 at this point.)

-- Now Session 2 can safely do its own modification:
UPDATE counters SET value = value - 30 WHERE name = 'widgets';

-- EXPECT: 120
SELECT value FROM counters WHERE name = 'widgets';

COMMIT;


-- TAKEAWAY:
--   FOR UPDATE is a pessimistic lock: contending writers wait for each
--   other instead of racing. Pros:
--     - simple to reason about, no retry loops
--     - works fine at READ COMMITTED, no need for SERIALIZABLE
--   Cons:
--     - serializes traffic on hot rows -- throughput suffers
--     - you can deadlock if you take locks in inconsistent order
--     - long-held locks block everyone behind them
--
--   Rule of thumb: if you have a small number of clearly-defined
--   "the real source of truth" rows you're about to update, FOR UPDATE
--   is often simpler and faster than SERIALIZABLE retries.
