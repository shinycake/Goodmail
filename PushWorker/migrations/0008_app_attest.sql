-- App Attest (src/attest-routes.ts): only the genuine app, signed by the owner's team, may register with the relay.
--
-- `attest_challenges` holds one-time challenges for attestations, each good for 5 minutes. `attest_keys` holds each
-- install's attested key: its ID (base64 of the SHA-256 of the public key), the uncompressed P-256 public key, the
-- App Attest environment, the highest assertion counter seen and when the key was last used. Nothing here names a
-- person or an account.
CREATE TABLE attest_challenges (
    challenge  TEXT    NOT NULL PRIMARY KEY,
    expires_at INTEGER NOT NULL
);

CREATE TABLE attest_keys (
    key_id       TEXT    NOT NULL PRIMARY KEY,
    public_key   BLOB    NOT NULL,
    environment  TEXT    NOT NULL CHECK (environment IN ('development', 'production')),
    counter      INTEGER NOT NULL,
    created_at   INTEGER NOT NULL,
    last_used_at INTEGER NOT NULL
);

CREATE INDEX attest_challenges_by_expiry ON attest_challenges (expires_at);
CREATE INDEX attest_keys_by_use ON attest_keys (last_used_at);
