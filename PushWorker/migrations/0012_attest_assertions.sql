-- The assertion counters each App Attest key has used lately (src/attest-routes.ts), so a request replayed within
-- the time skew is refused. Only counters within `REPLAY_WINDOW` of the key's newest (`attest_keys.counter`) are
-- kept: anything older is refused outright, and requests signed in turn may still arrive out of turn.
CREATE TABLE attest_assertions (
    key_id  TEXT    NOT NULL REFERENCES attest_keys (key_id) ON DELETE CASCADE,
    counter INTEGER NOT NULL,
    PRIMARY KEY (key_id, counter)
) WITHOUT ROWID;
