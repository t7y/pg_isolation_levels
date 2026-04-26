-- 00_setup.sql
--
-- Creates the tables and seed data used across all demos.
-- Idempotent: safe to run repeatedly. The reset.sql script will
-- truncate and reseed without dropping the schema.
--
-- Tables:
--   counters  - simple key/value, used to demonstrate non-repeatable reads
--               and basic write conflicts.
--   doctors   - the classic write-skew scenario: at least one doctor must
--               be on call. Each row has a boolean `on_call`.
--   accounts  - bank accounts with a non-negative balance invariant,
--               used to demonstrate lost-update / race conditions on writes.

CREATE TABLE IF NOT EXISTS counters (
    name  text PRIMARY KEY,
    value integer NOT NULL
);

CREATE TABLE IF NOT EXISTS doctors (
    id      integer PRIMARY KEY,
    name    text    NOT NULL,
    on_call boolean NOT NULL
);

CREATE TABLE IF NOT EXISTS accounts (
    id      integer PRIMARY KEY,
    owner   text    NOT NULL,
    balance numeric(12, 2) NOT NULL CHECK (balance >= 0)
);

-- Seed initial state. Use ON CONFLICT so 00_setup.sql is safe to re-run.
INSERT INTO counters (name, value) VALUES
    ('hits', 0),
    ('widgets', 100)
ON CONFLICT (name) DO UPDATE SET value = EXCLUDED.value;

INSERT INTO doctors (id, name, on_call) VALUES
    (1, 'Alice', true),
    (2, 'Bob',   true)
ON CONFLICT (id) DO UPDATE
    SET name    = EXCLUDED.name,
        on_call = EXCLUDED.on_call;

INSERT INTO accounts (id, owner, balance) VALUES
    (1, 'Alice', 100.00),
    (2, 'Bob',     0.00)
ON CONFLICT (id) DO UPDATE
    SET owner   = EXCLUDED.owner,
        balance = EXCLUDED.balance;
