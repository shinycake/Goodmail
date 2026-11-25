-- An IMAP login's state (src/imap-logins.ts) lives once per login here, instead of copied onto every device's watch
-- with that login, where two writes could leave the copies disagreeing and a refusal counted from a stale copy reset
-- the backoff. `state` is 'watching' or 'refused'; `refusals` counts the refusals in a row and `refused_at` is when
-- the last came (ms since 1970), both 0 while watching. A login whose watches have no row here (registered by a
-- build from before this table) is watching.
CREATE TABLE imap_logins (
    login_hash TEXT    NOT NULL PRIMARY KEY,
    state      TEXT    NOT NULL CHECK (state IN ('watching', 'refused')),
    refusals   INTEGER NOT NULL DEFAULT 0,
    refused_at INTEGER NOT NULL DEFAULT 0
);

-- Each login's state as its watches held it. Where they disagreed, a refusal wins, with the longest run, so no login
-- is tried sooner than its backoff allows.
INSERT INTO imap_logins (login_hash, state, refusals, refused_at)
SELECT login_hash,
       CASE WHEN MAX(state = 'refused') = 1 THEN 'refused' ELSE 'watching' END,
       MAX(CASE WHEN state = 'refused' THEN refusals ELSE 0 END),
       MAX(CASE WHEN state = 'refused' THEN refused_at ELSE 0 END)
FROM imap_watches
GROUP BY login_hash;

-- imap_watches keeps its state, refusals and refused_at columns, so the build from before this table runs on until
-- the new one is deployed, and stays safe to roll back to: the new build never reads them, and copies each login's
-- state onto them with every change (`mirrorLoginState`). A later migration drops them.
