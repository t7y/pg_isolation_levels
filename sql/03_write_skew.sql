-- 03_write_skew.sql
--
-- Anomaly: WRITE SKEW.
--
-- The classic example: a hospital requires that AT LEAST ONE doctor be
-- on call at all times. Two doctors, Alice and Bob, are both on call.
-- Each tries to go off call simultaneously. Each one checks "are there
-- still other doctors on call?", sees that yes there are, and proceeds
-- to take themselves off call. Both transactions commit successfully.
-- The result: nobody is on call. Invariant violated.
--
-- REPEATABLE READ does NOT prevent this. Each transaction's snapshot
-- shows the OTHER doctor still on call, so each UPDATE looks safe in
-- isolation. They write to DIFFERENT rows, so there's no row-level
-- conflict to detect, and RR only catches conflicts on the same row.
--
-- This is the canonical reason SERIALIZABLE exists. See 04_serializable.
--
-- Prerequisite: run /sql/reset.sql. (Both Alice and Bob start on_call=true.)


-- =====================================================================
-- SESSION 1 -- STEP 1: Alice opens an RR transaction.
-- =====================================================================
BEGIN ISOLATION LEVEL REPEATABLE READ;

-- EXPECT: count = 2
SELECT count(*) AS doctors_on_call FROM doctors WHERE on_call;


-- =====================================================================
-- SESSION 2 -- STEP 2: Bob opens an RR transaction.
-- =====================================================================
BEGIN ISOLATION LEVEL REPEATABLE READ;

-- EXPECT: count = 2  (Bob's snapshot also sees both on call)
SELECT count(*) AS doctors_on_call FROM doctors WHERE on_call;


-- =====================================================================
-- SESSION 1 -- STEP 3: Alice checks "any other on-call doctors?"
--                      and goes off call because the answer is yes.
-- =====================================================================
-- EXPECT: count = 1  (Bob is still on call from Alice's POV)
SELECT count(*) FROM doctors WHERE on_call AND id <> 1;

UPDATE doctors SET on_call = false WHERE id = 1;

COMMIT;


-- =====================================================================
-- SESSION 2 -- STEP 4: Bob does the symmetrical thing.
-- =====================================================================
-- EXPECT: count = 1  (Bob's snapshot still shows Alice on call)
--         Crucially, this commit will SUCCEED -- different rows, no
--         row-level conflict.
SELECT count(*) FROM doctors WHERE on_call AND id <> 2;

UPDATE doctors SET on_call = false WHERE id = 2;

COMMIT;


-- =====================================================================
-- AFTER -- check the damage from any session.
-- =====================================================================
-- EXPECT: 0  -- nobody is on call. Invariant violated.
SELECT count(*) AS doctors_on_call FROM doctors WHERE on_call;


-- TAKEAWAY:
--   REPEATABLE READ prevents non-repeatable reads and lost-update
--   conflicts on the SAME row, but it does NOT prevent write skew:
--   two transactions reading overlapping data and writing disjoint
--   rows in a way that violates a multi-row invariant.
--
--   To fix this you can either:
--     (a) use SERIALIZABLE (next demo), or
--     (b) explicitly lock the read with SELECT ... FOR UPDATE so the
--         second transaction blocks instead of running on a stale
--         snapshot (see 05_for_update.sql).
