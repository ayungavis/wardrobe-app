-- Account preferences (FR-099).
--
-- Onboarding completion, recent stickers, and last-used text style follow the
-- account so a second phone does not replay onboarding. A narrow table keyed by
-- account rather than columns on `account`: that row is read on every request,
-- and these values change often.

create table account_preference (
    account_id              uuid primary key references account (id) on delete cascade,
    -- A timestamp, not a boolean: null already means "not yet", and the date is
    -- worth having.
    onboarding_completed_at timestamptz,
    -- An ordered list that is never queried per element, which is what an array
    -- is for. The bound mirrors AccountPreferences.recentStickerLimit on iOS.
    recent_sticker_ids      text[]  not null default '{}'
        check (coalesce(array_length(recent_sticker_ids, 1), 0) <= 12),
    -- A small presentation struct that will keep changing shape and is never
    -- queried by field.
    last_text_style         jsonb   not null default '{}'
        check (jsonb_typeof(last_text_style) = 'object'),
    change_seq              bigint  not null,
    updated_at              timestamptz not null default now(),
    deleted_at              timestamptz
);

create trigger set_updated_at before update on account_preference
    for each row execute function set_updated_at();
