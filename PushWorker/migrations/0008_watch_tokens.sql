-- The Apple Watch (ADR-023): each registration may carry the paired watch's own APNs token, so an alert the iPhone
-- doesn't confirm can go to the watch instead. The iPhone renews it with its own registrations; the watch never
-- registers by itself. NULL when the device has no watch, or none that wants alerts.
ALTER TABLE devices ADD COLUMN watch_token TEXT;
ALTER TABLE graph_subscriptions ADD COLUMN watch_token TEXT;
ALTER TABLE imap_watches ADD COLUMN watch_token TEXT;

-- Alerts sent to an iPhone that has a watch, until it confirms them or the relay gives up waiting and tries the watch.
-- Only the alert's random ID, when it was sent and how its delivery stands ('sent', then 'confirmed' or 'fellBack'):
-- nothing about the mail or the account. Pruned by the cron run.
CREATE TABLE acks (
    alert_id TEXT    NOT NULL PRIMARY KEY,
    sent_at  INTEGER NOT NULL,
    delivery TEXT    NOT NULL CHECK (delivery IN ('sent', 'confirmed', 'fellBack'))
);

CREATE INDEX acks_by_sent ON acks (sent_at);
