-- Accounts are identified by HMAC-SHA256(lowercased email, EMAIL_HMAC_SECRET) in hex; raw addresses are never stored.

CREATE TABLE devices (
    account      TEXT    NOT NULL,
    device_token TEXT    NOT NULL,
    environment  TEXT    NOT NULL CHECK (environment IN ('sandbox', 'production')),
    updated_at   INTEGER NOT NULL,
    PRIMARY KEY (account, device_token)
);

-- Pruning removes a token from every account it was registered for.
CREATE INDEX devices_by_token ON devices (device_token);

-- The newest Gmail historyId pushed per account. Gmail history IDs are unsigned 64-bit, so they are kept as
-- 20-digit zero-padded text, which orders correctly as text without losing precision in JavaScript.
CREATE TABLE deliveries (
    account    TEXT NOT NULL PRIMARY KEY,
    history_id TEXT NOT NULL
);
