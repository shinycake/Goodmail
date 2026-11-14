-- When each Gmail account was last pushed. One email reaches Pub/Sub as a burst of history changes (the message,
-- then its labels), and the device catches up on all of them from the first push, so the rest are dropped.
CREATE TABLE push_times (
    account   TEXT    NOT NULL PRIMARY KEY,
    pushed_at INTEGER NOT NULL
);
