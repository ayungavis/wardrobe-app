-- Core schema: identity, sync backbone, wardrobe, media, challenge, jobs.
-- Rationale for every decision here lives in docs/backend-schema.md.
--
-- Two rules hold everywhere in this file:
--   1. No column has a uuid DEFAULT. Ids are UUIDv7 minted by the device
--      (FR-058, so retries upsert instead of duplicating) or by Rust.
--   2. Every synced table carries account_id, change_seq, and deleted_at.
--      The pull cursor is change_seq (FR-059); deletion is a tombstone that
--      travels the same feed as an ordinary update (FR-067).

-- ---------------------------------------------------------------- identity

create table account (
    -- Holds the per-account change counter that orders the whole sync feed.
    id            uuid primary key,
    -- Null while anonymous. UNIQUE permits many nulls, which is exactly right:
    -- anonymous accounts are numerous, Apple subjects are one per account.
    apple_subject text unique,
    change_seq    bigint      not null default 0,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    deleted_at    timestamptz
);

-- The client's Keychain UUID. Linking an anonymous identity to an Apple account
-- is a union by this id (FR-053), never a merge of similar-looking data.
create table account_device (
    anonymous_id uuid primary key,
    account_id   uuid        not null references account (id) on delete cascade,
    linked_at    timestamptz not null default now(),
    last_seen_at timestamptz
);
create index on account_device (account_id);

create table session (
    id         uuid primary key,
    account_id uuid        not null references account (id) on delete cascade,
    -- Hash only. A stolen database must not yield usable sessions (PRD §20 Security).
    token_hash bytea       not null unique,
    issued_at  timestamptz not null default now(),
    expires_at timestamptz not null,
    revoked_at timestamptz
);
create index on session (account_id);
create index on session (expires_at) where revoked_at is null;

-- ------------------------------------------------------------------- media

-- One row per object in R2/MinIO. This table is what makes account deletion
-- able to enumerate the objects it must remove (FR-071, §18.13).
create table media_object (
    id           uuid primary key,
    account_id   uuid        not null references account (id) on delete cascade,
    kind         text        not null check (kind in ('original', 'derivative', 'cutout', 'illustration')),
    -- Never public API; reads go through short-lived signed URLs (§18.5).
    storage_key  text        not null unique,
    content_type text        not null,
    byte_size    bigint check (byte_size >= 0),
    checksum     bytea,
    uploaded_at  timestamptz,
    created_at   timestamptz not null default now(),
    deleted_at   timestamptz
);
create index on media_object (account_id);

-- The original capture or confirmed import. Immutable content (§20.1).
create table photo (
    id              uuid primary key,
    account_id      uuid        not null references account (id) on delete cascade,
    media_object_id uuid        not null references media_object (id),
    source          text        not null check (source in ('capture', 'import')),
    captured_at     timestamptz,
    change_seq      bigint      not null,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    deleted_at      timestamptz
);
create index on photo (account_id, change_seq);
create index on photo (media_object_id);

-- Immutable versions of the flattened 1080x1920 export. Which one is current is
-- a pointer on the completion, not a flag here (FR-066).
create table photo_derivative (
    id              uuid primary key,
    account_id      uuid        not null references account (id) on delete cascade,
    photo_id        uuid        not null references photo (id) on delete cascade,
    media_object_id uuid        not null references media_object (id),
    change_seq      bigint      not null,
    created_at      timestamptz not null default now(),
    deleted_at      timestamptz
);
create index on photo_derivative (account_id, change_seq);
create index on photo_derivative (photo_id);
create index on photo_derivative (media_object_id);

-- ---------------------------------------------------------------- wardrobe

create table wardrobe_item (
    id                      uuid primary key,
    account_id              uuid        not null references account (id) on delete cascade,
    category                text        not null check (
        category in ('top', 'bottom', 'one-piece', 'outerwear', 'footwear', 'accessory')
    ),
    -- Nullable today because the iOS review UI does not collect them yet
    -- (PRD §13.4). They become required when that screen ships; the constraint
    -- moves here then rather than being faked now.
    name                    text check (length(name) <= 120),
    color                   text check (length(color) <= 60),
    garment_type            text check (length(garment_type) <= 60),
    -- Per-field merge bookkeeping (FR-062):
    --   {"name": {"rev": 3, "origin": "<device uuid>"}}
    -- Values stay in typed columns so real constraints still apply; only the
    -- revision bookkeeping is schemaless.
    attribute_revisions     jsonb       not null default '{}'
        check (jsonb_typeof(attribute_revisions) = 'object'),
    current_illustration_id uuid,
    illustration_state      text        not null default 'none' check (
        illustration_state in ('none', 'queued', 'rendering', 'ready', 'failed')
    ),
    change_seq              bigint      not null,
    created_at              timestamptz not null default now(),
    updated_at              timestamptz not null default now(),
    deleted_at              timestamptz
);
create index on wardrobe_item (account_id, change_seq);
create index on wardrobe_item (account_id, category) where deleted_at is null;

-- The losing candidate of a same-field concurrent edit, parked until the user
-- chooses (FR-062). Conflicts are rare, so they get their own narrow table
-- instead of widening the row every read touches.
create table wardrobe_item_conflict (
    id            uuid primary key,
    account_id    uuid        not null references account (id) on delete cascade,
    item_id       uuid        not null references wardrobe_item (id) on delete cascade,
    field         text        not null check (field in ('name', 'color', 'garment_type', 'category')),
    value         text,
    revision      bigint      not null,
    origin_device uuid,
    change_seq    bigint      not null,
    created_at    timestamptz not null default now(),
    resolved_at   timestamptz
);
create index on wardrobe_item_conflict (account_id, change_seq);
create index on wardrobe_item_conflict (item_id) where resolved_at is null;

-- Immutable version set; union by id, never overwritten (FR-063). An item
-- accumulates one per confirmed wear, which is what makes matching improve.
create table item_fingerprint (
    id              uuid primary key,
    account_id      uuid        not null references account (id) on delete cascade,
    item_id         uuid        not null references wardrobe_item (id) on delete cascade,
    version         text        not null,
    color_lab       real[]      not null,
    aspect_ratio    real        not null,
    feature_print   bytea       not null,
    mask_quality    real        not null check (mask_quality >= 0 and mask_quality <= 1),
    source_photo_id uuid references photo (id) on delete set null,
    change_seq      bigint      not null,
    created_at      timestamptz not null default now(),
    deleted_at      timestamptz
);
create index on item_fingerprint (account_id, change_seq);
create index on item_fingerprint (item_id);
create index on item_fingerprint (source_photo_id);

create table item_cutout (
    id              uuid primary key,
    account_id      uuid        not null references account (id) on delete cascade,
    item_id         uuid        not null references wardrobe_item (id) on delete cascade,
    media_object_id uuid        not null references media_object (id),
    source_photo_id uuid references photo (id) on delete set null,
    change_seq      bigint      not null,
    created_at      timestamptz not null default now(),
    deleted_at      timestamptz
);
create index on item_cutout (account_id, change_seq);
create index on item_cutout (item_id);
create index on item_cutout (media_object_id);
create index on item_cutout (source_photo_id);

-- Immutable outputs carrying their own provenance, so a model change can never
-- rewrite what an older model produced (§20.1 conflict rules).
create table item_illustration (
    id              uuid primary key,
    account_id      uuid        not null references account (id) on delete cascade,
    item_id         uuid        not null references wardrobe_item (id) on delete cascade,
    media_object_id uuid        not null references media_object (id),
    style_version   text        not null,
    model           text        not null,
    prompt_version  text        not null,
    change_seq      bigint      not null,
    created_at      timestamptz not null default now(),
    deleted_at      timestamptz
);
create index on item_illustration (account_id, change_seq);
create index on item_illustration (item_id);
create index on item_illustration (media_object_id);

-- Deferred: wardrobe_item and item_illustration point at each other, and the
-- worker writes both in one transaction.
alter table wardrobe_item
    add constraint wardrobe_item_current_illustration_fkey
    foreign key (current_illustration_id) references item_illustration (id)
    on delete set null
    deferrable initially deferred;
create index on wardrobe_item (current_illustration_id);

-- --------------------------------------------------------------- challenge

create table challenge_card (
    id             uuid primary key,
    -- Null for the curated catalog, which is global and the permanent fallback
    -- whenever generation is unavailable (FR-008, FR-080).
    account_id     uuid references account (id) on delete cascade,
    source         text        not null check (source in ('curated', 'generated')),
    prompt_text    text        not null,
    locale         text        not null,
    model          text,
    prompt_version text,
    created_at     timestamptz not null default now(),
    retired_at     timestamptz,
    -- Generated copy must always name the model that produced it (FR-073).
    check (source = 'curated' or model is not null)
);
create index on challenge_card (account_id);
create index on challenge_card (locale) where retired_at is null and source = 'curated';

create table active_challenge (
    id          uuid primary key,
    account_id  uuid        not null references account (id) on delete cascade,
    card_id     uuid        not null references challenge_card (id),
    accepted_at timestamptz not null,
    -- Computed on the device: the server must never guess a user's time zone.
    local_date  date        not null,
    time_zone   text        not null,
    photo_id    uuid references photo (id) on delete set null,
    change_seq  bigint      not null,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    deleted_at  timestamptz
);
create unique index on active_challenge (account_id) where deleted_at is null;
create index on active_challenge (account_id, change_seq);
create index on active_challenge (card_id);
create index on active_challenge (photo_id);

create table challenge_completion (
    id                    uuid primary key,
    account_id            uuid        not null references account (id) on delete cascade,
    card_id               uuid        not null references challenge_card (id),
    local_date            date        not null,
    time_zone             text        not null,
    completed_at          timestamptz not null,
    -- Two offline devices may both complete the same local day. The earliest is
    -- canonical, the other is preserved as a conflict whose wears do not count
    -- until the user resolves it (FR-065).
    status                text        not null check (status in ('canonical', 'conflicting', 'superseded')),
    photo_id              uuid references photo (id) on delete set null,
    current_derivative_id uuid references photo_derivative (id) on delete set null,
    change_seq            bigint      not null,
    created_at            timestamptz not null default now(),
    updated_at            timestamptz not null default now(),
    deleted_at            timestamptz
);
-- A partial unique index cannot be an ON CONFLICT target, so the write path is
-- an explicit transaction: lock the account, look for today's canonical row,
-- then insert as canonical or conflicting. That is deliberate.
create unique index on challenge_completion (account_id, local_date)
    where status = 'canonical' and deleted_at is null;
create index on challenge_completion (account_id, change_seq);
create index on challenge_completion (card_id);
create index on challenge_completion (photo_id);
create index on challenge_completion (current_derivative_id);

-- -------------------------------------------------------------------- wear

create table wear_record (
    id              uuid primary key,
    account_id      uuid        not null references account (id) on delete cascade,
    item_id         uuid        not null references wardrobe_item (id) on delete cascade,
    completion_id   uuid references challenge_completion (id) on delete set null,
    source_photo_id uuid references photo (id) on delete set null,
    worn_on         date        not null,
    -- A correction revises this row; it never creates a second wear (FR-064).
    revision        integer     not null default 1 check (revision >= 1),
    change_seq      bigint      not null,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    deleted_at      timestamptz,
    -- One wear per confirmed item/source-photo occurrence. Postgres allows many
    -- nulls here, and that is correct: manual wears carry no source photo and
    -- are legitimately repeatable.
    unique (account_id, item_id, source_photo_id)
);
create index on wear_record (account_id, change_seq);
create index on wear_record (item_id) where deleted_at is null;
create index on wear_record (completion_id);
create index on wear_record (source_photo_id);

-- -------------------------------------------------------------------- jobs

create table job (
    id           uuid primary key,
    account_id   uuid references account (id) on delete cascade,
    kind         text        not null,
    -- One job per new item (FR-070). A retried enqueue hits this key instead of
    -- rendering, and paying for, a second illustration.
    dedupe_key   text        not null,
    payload      jsonb       not null default '{}' check (jsonb_typeof(payload) = 'object'),
    status       text        not null default 'pending'
        check (status in ('pending', 'running', 'succeeded', 'failed')),
    attempts     integer     not null default 0 check (attempts >= 0),
    max_attempts integer     not null default 3 check (max_attempts >= 1),
    run_after    timestamptz not null default now(),
    started_at   timestamptz,
    finished_at  timestamptz,
    -- A classified code, never a provider message: raw responses may carry user
    -- content and are forbidden from anything log-shaped (§18.12).
    last_error_code text,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now(),
    unique (kind, dedupe_key)
);
-- Keeps the FOR UPDATE SKIP LOCKED claim cheap once the table accumulates
-- finished rows.
create index on job (run_after) where status = 'pending';
create index on job (account_id);
