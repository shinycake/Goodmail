-- Mail an Outlook account sends itself alerts like any other, as Apple Mail does, so the relay no longer keeps the
-- hash of the account's address.
ALTER TABLE graph_grants DROP COLUMN own_address_hash;
