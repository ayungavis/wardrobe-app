-- Refresh-token rotation with reuse detection.
--
-- session held one token and an expiry. The agreed model is a 30-day access
-- token plus a 180-day refresh token that rotates on every use: presenting a
-- refresh token that has already been rotated means it was stolen, and the whole
-- family goes with it.

alter table session
    -- Makes "sign out of this device" possible, and makes reuse detection mean
    -- something more specific than "somebody, somewhere".
    add column device_id          uuid references account_device (anonymous_id) on delete set null,
    add column family_id          uuid,
    add column refresh_token_hash bytea unique,
    add column refresh_expires_at timestamptz,
    -- Set when this row's refresh token is exchanged. A second exchange of the
    -- same token is therefore detectable rather than merely unlikely.
    add column rotated_at         timestamptz;

-- The table is empty today, but a migration that assumes emptiness is a
-- migration that breaks in the first environment that is not empty.
update session set family_id = id where family_id is null;
alter table session alter column family_id set not null;

create index on session (family_id);
create index on session (device_id);
