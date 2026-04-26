# Your Postgres transactions are probably broken (and you don't know it)

Most backend engineers can tell you that Postgres has transaction isolation levels. Far fewer can tell you what Read Committed — the default — actually lets through. Even fewer have seen it happen.

I built a small sandbox to make these bugs visible: two `psql` sessions, side by side, running the exact SQL that breaks. No application code, no ORM magic, no hand-waving. Just the raw behavior of the database you rely on every day.

**Repo: [github.com/t7y/pg_isolation_levels](https://github.com/t7y/pg_isolation_levels)**

Here's what I learned by actually watching it fail.

But first, a question to hold in your head as you read: **if you were building a double-entry ledger — the kind that moves real money — what isolation level would you use?** By the end, you'll have a strong opinion.

---

## The default is leakier than you think

Postgres ships with Read Committed. The name sounds safe. It is not.

Open two `psql` sessions. In the first, start a transaction and read a counter:

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT value FROM counters WHERE name = 'widgets';
-- 100
```

In the second session, update that counter and commit:

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
UPDATE counters SET value = 200 WHERE name = 'widgets';
COMMIT;
```

Back in the first session — still inside the same transaction — read it again:

```sql
SELECT value FROM counters WHERE name = 'widgets';
-- 200
```

The value changed mid-transaction. Same query, same transaction, different result. This is a **non-repeatable read**, and it's the documented, expected behavior of the default isolation level.

If your code reads a value, makes a decision, and writes back — another commit can change what you read between those steps.

## Repeatable Read fixes reads but breaks writes

Bump up to Repeatable Read and the snapshot stabilizes. Every statement in the transaction sees the database as it was when the transaction started. No more phantom value changes.

But try to *write* a row that someone else modified since your snapshot was taken:

```sql
UPDATE counters SET value = value + 1 WHERE name = 'widgets';
-- ERROR: could not serialize access due to concurrent update
-- SQLSTATE: 40001
```

Postgres refuses. Your snapshot is stale and it won't silently apply your write on top of someone else's. The only option is to roll back and retry the entire transaction from scratch.

This is a good trade-off for read-heavy workloads that need consistency. But it means your application code needs a retry loop around any transaction that writes.

## The bug nobody catches: write skew

Here's where it gets interesting. A hospital requires at least one doctor on call at all times. Alice and Bob are both on call. Both try to go off call simultaneously.

Under Repeatable Read, each transaction checks "is someone else on call?" — sees yes (the other doctor) — and sets themselves to off call. Both transactions commit. Neither conflicts because they write to **different rows**.

Result: zero doctors on call. Invariant violated. No error raised.

```sql
-- Session 1 (Alice)
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT count(*) FROM doctors WHERE on_call AND id <> 1;  -- 1 (Bob)
UPDATE doctors SET on_call = false WHERE id = 1;
COMMIT;  -- succeeds

-- Session 2 (Bob), concurrently
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT count(*) FROM doctors WHERE on_call AND id <> 2;  -- 1 (Alice, per snapshot)
UPDATE doctors SET on_call = false WHERE id = 2;
COMMIT;  -- also succeeds
```

This is **write skew**: two transactions read overlapping data and write disjoint rows in a way that violates a constraint that spans multiple rows. Repeatable Read can't detect it because there's no row-level conflict.

## Serializable catches it

Run the same scenario under Serializable and Postgres tracks the *predicate reads* — which rows each transaction's WHERE clauses depended on. It detects the circular dependency and aborts the second transaction:

```
ERROR: could not serialize access due to read/write dependencies among transactions
SQLSTATE: 40001
Hint: The transaction might succeed if retried.
```

The first commit wins. The second must retry. On retry it sees one doctor on call and the application logic correctly refuses to take the last one off duty.

Serializable gives you correctness as if every transaction ran one at a time, without requiring any explicit locks. The cost is that your code must handle `40001` retries.

## The practical escape hatch: `SELECT ... FOR UPDATE`

Serializable is the most correct option. But most production systems don't use it. The retry logic is invasive, and for many workloads there's a simpler answer: pessimistic locking.

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT balance FROM accounts WHERE id = 1 FOR UPDATE;
-- row is locked until this transaction ends
```

`FOR UPDATE` says: "I'm about to read this, decide something, and write it back — nobody else touch it." The second transaction blocks on the `SELECT`, not the `UPDATE`. When it unblocks after the first transaction commits, it reads the *real* committed value and can compute correctly.

## Where this matters most: money

These aren't academic curiosities. They're the exact class of bug that shows up in financial systems — ledgers, payment processors, anything that moves balances between accounts.

The balance transfer demo in the repo makes this visceral. Two concurrent transfers from Alice to Bob. Both read her balance as $100. Both compute new balances as literals and write them back:

| | Session 1 ($60 transfer) | Session 2 ($30 transfer) |
|---|---|---|
| Read Alice | 100 | 100 |
| Compute | Alice = 40, Bob = 60 | Alice = 70, Bob = 30 |
| Write | Alice = 40, Bob = 60 | Alice = 70, Bob = 30 |

End state: Alice = $70, Bob = $30. Session 1's $60 transfer vanished. No error. No constraint violation. The total is still $100, so nothing looks wrong — except that one customer's money didn't move.

Add `FOR UPDATE` and Session 2 blocks on the read. When it unblocks it sees Alice = $40, computes correctly, and both transfers land: Alice = $10, Bob = $90.

Now imagine this at scale: thousands of concurrent transfers, and every lost update is a silent accounting discrepancy that only surfaces during reconciliation — days or weeks later, buried in millions of rows, with no error trail to follow.

## The cheat sheet

| Level | Non-repeatable reads | Lost updates (same row) | Write skew (cross-row) | Retry needed |
|---|---|---|---|---|
| Read Committed | Yes | Yes | Yes | No |
| Repeatable Read | No | No (40001) | **Yes** | Yes |
| Serializable | No | No (40001) | No (40001) | Yes |
| RC + `FOR UPDATE` | Scoped | No (blocks) | Depends | No |

## When to use what

**Read Committed** is fine for queries that don't feed into writes. Dashboards, reports, one-off SELECTs.

**Repeatable Read** is good when you need a consistent snapshot for read-heavy logic. Reports that join many tables and need them to agree.

**Serializable** is the right choice when you have multi-row invariants and the "what to lock" question doesn't have an obvious answer. The doctors-on-call problem is the canonical example.

**`SELECT ... FOR UPDATE`** is the pragmatic choice when the lock target is obvious — an account row, an inventory row, a reservation slot. No retry loop, simple to reason about, and it works at Read Committed.

## So what isolation level should a double-entry ledger use?

Now we have enough context to answer the question from the top.

A double-entry ledger has two invariants that must hold at all times:

1. **Every journal entry balances.** Debits and credits within a single logical transaction sum to zero.
2. **Account balances stay valid.** The running balance of any account (the sum of all its entries) must never violate a constraint — typically non-negative for asset accounts.

The threat model is two concurrent transactions both reading an account's balance, both deciding the transfer is affordable, and both inserting entries. They're writing *new rows*, not updating the same row, so there's no row-level conflict for Repeatable Read to catch. This is write skew — the same pattern as the doctors going off call.

**Serializable** is the theoretically correct answer. SSI tracks the predicate reads on the entries table and detects when two transactions depend on each other's writes. One gets aborted with `40001`, retries, and sees the truth. No locks to manage, no rows to remember to lock. Correctness falls out of the isolation level.

**But most production ledgers use Read Committed + `SELECT ... FOR UPDATE`.** Here's why:

- **The lock target is obvious.** Every ledger has an `accounts` table (or equivalent). Lock the account row before reading the balance. The second transaction waits instead of racing. When it unblocks, it sees the real balance and can decide correctly.
- **No retry loops.** Serializable requires every write path to handle `40001` and replay the entire transaction. `FOR UPDATE` serializes access at the point of contention — the blocked transaction simply waits and then proceeds. The application code stays linear.
- **Predictable latency.** With Serializable, you find out about the conflict at commit time, after doing all the work. With `FOR UPDATE`, you find out immediately — on the `SELECT`. The second transaction knows it's waiting from the start.
- **Battle-tested at scale.** Stripe, Square, most banking cores — the systems that move real money overwhelmingly use pessimistic locking on the account row under Read Committed, not Serializable.

The pattern looks like this:

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;

SELECT balance FROM accounts WHERE id = :account_id FOR UPDATE;
-- row is locked; concurrent transactions wait here

-- Application validates the transfer is allowed
INSERT INTO journal_entries (account_id, amount, ...) VALUES (:account_id, -80.00, ...);
UPDATE accounts SET balance = balance - 80.00 WHERE id = :account_id;
-- CHECK (balance >= 0) is the last line of defense

COMMIT;
```

`FOR UPDATE` is the lock. The `CHECK` constraint is the safety net. Together they give you correctness without retry complexity.

**Use Serializable when the invariants are complex and span many tables in ways where the "what to lock" question doesn't have an obvious answer.** Use `FOR UPDATE` when the lock target is clear — and in a ledger, it's always clear: it's the account.

## Try it yourself

The whole thing runs with one command:

```bash
git clone https://github.com/t7y/pg_isolation_levels.git
cd pg_isolation_levels
cp .env.example .env
docker compose up -d
```

Open two terminals, run `./scripts/psql.sh` in each, and work through the demos in `sql/` one step at a time. Each file tells you which session to run which statement in, and what to expect.

The bugs are much more convincing when you watch them happen in real time.

---

*The repo is at [github.com/t7y/pg_isolation_levels](https://github.com/t7y/pg_isolation_levels). PRs welcome if you want to add more anomaly demos.*
