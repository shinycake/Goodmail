-- Outlook: each device makes its own Microsoft Graph subscription to its account's Inbox, and registers it here.
-- Graph sends the subscription's ID and its clientState with every notification; only the device and Graph know the
-- clientState, so it proves a notification is real and a registration is the subscription owner's. Only its
-- SHA-256 is stored. `account` is the app's own opaque account ID, never an address.
CREATE TABLE graph_subscriptions (
    subscription_id   TEXT    NOT NULL PRIMARY KEY,
    client_state_hash TEXT    NOT NULL,
    account           TEXT    NOT NULL,
    device_token      TEXT    NOT NULL,
    environment       TEXT    NOT NULL CHECK (environment IN ('sandbox', 'production')),
    expires_at        INTEGER NOT NULL
);

CREATE INDEX graph_subscriptions_by_token ON graph_subscriptions (device_token);
CREATE INDEX graph_subscriptions_by_expiry ON graph_subscriptions (expires_at);
