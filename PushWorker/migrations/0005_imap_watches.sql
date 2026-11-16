-- iCloud and other IMAP accounts: their servers push nothing to anyone but Apple Mail, so the relay looks at each
-- watched Inbox itself every minute (a cron trigger) and alerts when its UIDNEXT grows. Each device registers its own
-- watch, like an Outlook subscription: watch_id and a random secret only the device knows (only its SHA-256 is kept).
-- `account` is the app's opaque account ID, never an address.
--
-- `login` is the server, user name and password, sealed with AES-GCM under a key derived from EMAIL_HMAC_SECRET.
-- `login_hash` (HMAC-SHA256 under the same secret) tells a renewal with the same login, which needs no new check,
-- from a changed one, and groups watches of the same mailbox so it is looked at once a minute however many devices
-- watch it. `state` is 'watching', or 'refused' once the server refused the login: the relay never tries it again,
-- so it can't lock the account, until the device registers another login.
CREATE TABLE imap_watches (
    watch_id     TEXT    NOT NULL PRIMARY KEY,
    secret_hash  TEXT    NOT NULL,
    account      TEXT    NOT NULL,
    device_token TEXT    NOT NULL,
    environment  TEXT    NOT NULL CHECK (environment IN ('sandbox', 'production')),
    login        TEXT    NOT NULL,
    login_hash   TEXT    NOT NULL,
    state        TEXT    NOT NULL CHECK (state IN ('watching', 'refused')),
    uid_validity INTEGER NOT NULL,
    uid_next     INTEGER NOT NULL,
    expires_at   INTEGER NOT NULL
);

CREATE INDEX imap_watches_by_token ON imap_watches (device_token);
CREATE INDEX imap_watches_by_login ON imap_watches (login_hash);
CREATE INDEX imap_watches_by_expiry ON imap_watches (expires_at);
