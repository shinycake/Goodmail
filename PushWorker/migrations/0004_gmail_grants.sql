-- Gmail: the app's own refresh token for an account, which lets the relay look at the history a Pub/Sub
-- notification announces and alert only when new mail reached the Inbox. The token is AES-GCM encrypted under a key
-- derived from EMAIL_HMAC_SECRET; token_hash (HMAC-SHA256 under the same secret) lets the app send it again without
-- the relay calling Google each time. Without a row, every notification alerts.
CREATE TABLE gmail_grants (
    account       TEXT    NOT NULL PRIMARY KEY,
    refresh_token TEXT    NOT NULL,
    token_hash    TEXT    NOT NULL,
    updated_at    INTEGER NOT NULL
);
CREATE INDEX gmail_grants_token_hash ON gmail_grants (token_hash);
