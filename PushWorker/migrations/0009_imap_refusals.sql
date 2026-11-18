-- A refused IMAP login is tried again (src/imap-watches.ts `isDue`): a server can refuse a good login once, and a
-- watch that stopped for good after one refusal left its device without alerts until someone noticed. `refusals`
-- counts the refusals in a row and `refused_at` is when the last one came (ms since 1970); both are 0 while watching.
-- A watch refused before this migration has 0 refusals, so the next cron run tries it.
ALTER TABLE imap_watches ADD COLUMN refusals INTEGER NOT NULL DEFAULT 0;
ALTER TABLE imap_watches ADD COLUMN refused_at INTEGER NOT NULL DEFAULT 0;
