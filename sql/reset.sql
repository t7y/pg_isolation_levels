-- reset.sql
--
-- Returns every demo table to its initial seeded state.
-- Run this between demos so each one starts from a known baseline.
--
-- Implementation: ensure the schema exists by sourcing 00_setup.sql
-- (which is idempotent), then TRUNCATE and reseed so any rows added
-- mid-demo are removed.

\i /sql/00_setup.sql

TRUNCATE counters, doctors, accounts;

INSERT INTO counters (name, value) VALUES
    ('hits', 0),
    ('widgets', 100);

INSERT INTO doctors (id, name, on_call) VALUES
    (1, 'Alice', true),
    (2, 'Bob',   true);

INSERT INTO accounts (id, owner, balance) VALUES
    (1, 'Alice', 100.00),
    (2, 'Bob',     0.00);
