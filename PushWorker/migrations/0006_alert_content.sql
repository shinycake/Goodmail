-- The relay alerts only for mail it has read the sender and subject of (src/new-mail.ts), so it needs a way into
-- every mailbox it alerts for.
--
-- Gmail: `primary_only` is the app's Primary Only choice, so the check skips other categories as the app does, and
-- `history_id` is the account's history ID when the token was stored, which the first notification checks from.
ALTER TABLE gmail_grants ADD COLUMN primary_only INTEGER NOT NULL DEFAULT 0;
ALTER TABLE gmail_grants ADD COLUMN history_id TEXT;

-- Outlook: the app's own refresh token for an account, sent with a Graph subscription's clientState so only the
-- device that made the subscription can set it. Sealed like Gmail's; `token_hash` tells a token already held, and
-- `own_address_hash` (HMAC of the account's address) tells mail the account sent itself. Microsoft hands out a new
-- refresh token on each refresh, and the newest is kept.
CREATE TABLE graph_grants (
    account          TEXT    NOT NULL PRIMARY KEY,
    refresh_token    TEXT    NOT NULL,
    token_hash       TEXT    NOT NULL,
    own_address_hash TEXT    NOT NULL,
    updated_at       INTEGER NOT NULL
);
CREATE INDEX graph_grants_token_hash ON graph_grants (token_hash);
