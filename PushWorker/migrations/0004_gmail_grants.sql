-- Gmail: an account's read-only metadata grant (scope gmail.metadata, nothing else), which lets the relay look at
-- the history a Pub/Sub notification announces and alert only when new mail reached the Inbox. The refresh token is
-- AES-GCM encrypted under a key derived from EMAIL_HMAC_SECRET. Without a row, every notification alerts.
CREATE TABLE gmail_grants (
    account       TEXT    NOT NULL PRIMARY KEY,
    refresh_token TEXT    NOT NULL,
    updated_at    INTEGER NOT NULL
);
