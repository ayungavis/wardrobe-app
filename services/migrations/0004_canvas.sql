-- Canvas documents and the photos a completion owns (FR-094–FR-097).
--
-- backend-schema.md §5 deferred canvas documents while the PRD was v3.1. v3.3
-- made them Must, and they land in the same ✓ transaction as the completion —
-- adding them later would mean rewriting that write path.

-- The document payload and the undo history are objects, not columns.
alter table media_object drop constraint media_object_kind_check;
alter table media_object add constraint media_object_kind_check check (
    kind in ('original', 'derivative', 'cutout', 'illustration', 'document', 'history')
);

-- Immutable versions of the layered document. The payload lives in the object
-- store rather than a jsonb column: it carries freehand strokes, PRD §28 still
-- lists its size ceiling as open, and as a media_object it stays enumerable for
-- account deletion (FR-071) while the change feed stays metadata-only.
create table canvas_document (
    id                      uuid primary key,
    account_id              uuid    not null references account (id) on delete cascade,
    completion_id           uuid    not null references challenge_completion (id) on delete cascade,
    derivative_id           uuid    not null references photo_derivative (id) on delete cascade,
    schema_version          integer not null check (schema_version >= 1),
    media_object_id         uuid    not null references media_object (id),
    -- Nullable on purpose. FR-096 requires a failed document to retry on its own
    -- while its derivative stays viewable, so a failed undo-history upload must
    -- not make the document itself useless.
    history_media_object_id uuid references media_object (id),
    history_step_count      integer check (history_step_count between 0 and 10),
    change_seq              bigint  not null,
    created_at              timestamptz not null default now(),
    deleted_at              timestamptz,
    -- FR-095: every saved derivative is paired with exactly the document version
    -- that produced it. A database rule, not a convention the write path has to
    -- remember.
    unique (derivative_id)
);
create index on canvas_document (account_id, change_seq);
create index on canvas_document (completion_id);
create index on canvas_document (media_object_id);
create index on canvas_document (history_media_object_id);

-- FR-093 allows several photo layers, and ActiveChallenge.importedPhotoIDs shows
-- iOS already uses it. challenge_completion.photo_id is singular, so the extra
-- photos were named only inside the document payload — where FR-097's deletion
-- and FR-071's object enumeration cannot reach them.
create table completion_photo (
    completion_id uuid not null references challenge_completion (id) on delete cascade,
    photo_id      uuid not null references photo (id) on delete cascade,
    role          text not null check (role in ('primary', 'layer')),
    primary key (completion_id, photo_id)
);
create index on completion_photo (photo_id);
create unique index on completion_photo (completion_id) where role = 'primary';
