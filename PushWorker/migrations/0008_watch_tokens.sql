-- The Apple Watch (ADR-023): each registration may carry the paired watch's own APNs token, so an alert the iPhone
-- doesn't confirm can go to the watch instead. The iPhone renews it with its own registrations; the watch never
-- registers by itself. NULL when the device has no watch, or none that wants alerts.
ALTER TABLE devices ADD COLUMN watch_token TEXT;
ALTER TABLE graph_subscriptions ADD COLUMN watch_token TEXT;
ALTER TABLE imap_watches ADD COLUMN watch_token TEXT;

-- Alerts sent to an iPhone, until it confirms them or the relay gives up waiting and tries its watch. Only the alert's
-- random ID and when it was sent: nothing about the mail or the account. Pruned by the cron run.
CREATE TABLE acks (
    alert_id     TEXT    NOT NULL PRIMARY KEY,
    sent_at      INTEGER NOT NULL,
    confirmed_at INTEGER
);

CREATE INDEX acks_by_sent ON acks (sent_at);
