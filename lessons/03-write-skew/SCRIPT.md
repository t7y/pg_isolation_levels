# Demo 3: Write Skew - The Anomaly Repeatable Read Can't Catch

**Teaching Script.** Follow `.cursor/SCRIPT_INSTRUCTIONS.md`. Source of truth for SQL: `sql/03_write_skew.sql`. You guide; the learner runs everything in Session 1 / Session 2.

---

## What this demo proves

The classic **write skew** scenario. A hospital requires that **at least one doctor be on call** at all times. Alice and Bob are both on call. Each, simultaneously, checks "is another doctor still on call?", sees yes, and takes themselves off call. Both commit. Result: **nobody is on call** — invariant violated.

**REPEATABLE READ does NOT prevent this.** Each transaction's snapshot shows the *other* doctor on call, so each update looks safe in isolation. They write to *different rows*, so there's no row-level conflict to detect — and Repeatable Read only catches conflicts on the *same* row. This is the canonical reason SERIALIZABLE exists (demo 4).

---

## Step 0: Reset

**Say:**

"Reset so both doctors start on call:
```bash
./scripts/reset.sh
```
After reset, Alice (id 1) and Bob (id 2) both have `on_call = true`. Keep both sessions open."

**STOP:** Confirm reset.
**USER:** Confirms.

---

## Step 1: Session 1 (Alice) opens RR and reads

**Say:**

"Think of **Session 1 as Alice** and **Session 2 as Bob**. In **Session 1**, paste:
```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- EXPECT: count = 2
SELECT count(*) AS doctors_on_call FROM doctors WHERE on_call;
```
Two doctors on call. Leave it open."

**STOP:** Count?
**USER:** Reports `2`.

---

## Step 2: Session 2 (Bob) opens RR and reads

**Say:**

"In **Session 2**, paste:
```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- EXPECT: count = 2
SELECT count(*) AS doctors_on_call FROM doctors WHERE on_call;
```
Bob's snapshot also sees both on call. Both transactions are now open on the same starting picture."

**STOP:** Count?
**USER:** Reports `2`.

---

## Step 3: Session 1 (Alice) checks for others, then goes off call

**Say:**

"In **Session 1**, Alice checks 'is anyone *else* on call?' and, seeing yes, takes herself off. Paste:
```sql
-- EXPECT: count = 1  (Bob still on call from Alice's POV)
SELECT count(*) FROM doctors WHERE on_call AND id <> 1;
UPDATE doctors SET on_call = false WHERE id = 1;
COMMIT;
```
Alice's check said 'Bob's still here, so it's safe for me to leave' — and she committed."

**STOP:** Did the count read `1` and the commit succeed?
**USER:** Confirms `1` then `COMMIT`.

---

## Step 4: Session 2 (Bob) does the symmetric thing

**Say:**

"Now **Session 2**, Bob runs the mirror image. Paste:
```sql
-- EXPECT: count = 1  (Bob's snapshot still shows Alice on call)
SELECT count(*) FROM doctors WHERE on_call AND id <> 2;
UPDATE doctors SET on_call = false WHERE id = 2;
COMMIT;
```

Crucial question: did Bob's commit **succeed** or get rejected?"

**STOP:** What happened on Bob's commit?
**USER:** Reports the count was `1` and the `COMMIT` **succeeded** (no error).

**Say:**

"Right — it succeeded with no complaint. Bob's snapshot (taken in Step 2) still shows Alice on call, so his check said 'safe to leave.' Alice and Bob wrote to *different rows* (id 1 vs id 2), so Repeatable Read sees no conflict to abort."

---

## Step 5: Inspect the damage

**Say:**

"Let's see the result. In **either** session, paste:
```sql
-- EXPECT: 0  <- nobody is on call. Invariant violated.
SELECT count(*) AS doctors_on_call FROM doctors WHERE on_call;
```"

**STOP:** Count?
**USER:** Reports `0`.

**Say:**

"Zero doctors on call. Both transactions individually looked correct, both committed successfully, and together they broke the invariant. That's write skew."

---

## Wrap-up

**Say:**

"**Takeaway:** REPEATABLE READ prevents non-repeatable reads and same-row lost-update conflicts — but NOT write skew, where two transactions read overlapping data and write *disjoint* rows in a way that violates a multi-row invariant.

Two fixes:
- **SERIALIZABLE** — Postgres detects the dangerous read/write dependency and aborts one transaction (that's `/start-4`, where we replay this exact scenario)
- **`SELECT ... FOR UPDATE`** — explicitly lock the rows you read so the second transaction blocks instead of running on a stale snapshot (that's `/start-5`)

Type `/start-4` to watch Serializable catch what we just got away with."

**STOP:** Answer questions, then point to `/start-4`.

---

## Notes for You

- Relay SQL verbatim from `sql/03_write_skew.sql`.
- The pivotal beat is Step 4: emphasize that Bob's commit **succeeds** — that's the whole anomaly. Don't let the learner expect an error here; the error only shows up under Serializable in demo 4.
- Keep the Alice=Session 1, Bob=Session 2 mapping consistent.
