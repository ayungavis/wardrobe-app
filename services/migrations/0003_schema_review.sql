-- Review fixes. Nine findings from checking 0001/0002 against PostgreSQL practice.
-- None of these rewrites data; all of them are cheaper now than after the write
-- paths exist.

-- --------------------------------------------------------------- hot rows

-- Every mutation runs `update account set change_seq = change_seq + 1` on a row
-- that every authenticated request also reads. change_seq is unindexed so the
-- update can be HOT, but only while the page still has free space.
alter table account set (fillfactor = 70);

-- Becomes update-heavy once refresh rotation lands in 0005.
alter table session set (fillfactor = 90);

-- ------------------------------------------------------------ job claiming

-- claim_job() filters on kind; the original index carried only run_after, so a
-- worker looking for one kind scanned and discarded rows of every other kind.
drop index if exists job_run_after_idx;
create index on job (kind, run_after) where status = 'pending';

-- ------------------------------------------------------------ missing data

-- Present on iOS, user-editable, and now searched. Without it a user's edit
-- would not survive restore.
alter table wardrobe_item add column description text check (length(description) <= 500);

-- ------------------------------------------------------------- value bounds

-- CIE Lab is exactly three components. Without this a malformed array is
-- storable and the matching code meets it at read time instead.
alter table item_fingerprint
    add constraint item_fingerprint_color_lab_length check (array_length(color_lab, 1) = 3);

-- User-supplied text with no ceiling. A buggy client could otherwise store
-- megabytes in a column read on every request.
alter table challenge_card
    add constraint challenge_card_prompt_text_length check (length(prompt_text) <= 500);
alter table media_object
    add constraint media_object_content_type_length check (length(content_type) <= 120);
alter table media_object
    add constraint media_object_storage_key_length check (length(storage_key) <= 500);
alter table active_challenge
    add constraint active_challenge_time_zone_length check (length(time_zone) <= 64);
alter table challenge_completion
    add constraint challenge_completion_time_zone_length check (length(time_zone) <= 64);

-- ----------------------------------------------------------------- indexes

-- FR-038: the History grid orders newest first and had no index for it.
create index on challenge_completion (account_id, completed_at desc) where deleted_at is null;

-- FR-062: the conflict's origin device was an unenforced uuid.
alter table wardrobe_item_conflict
    add constraint wardrobe_item_conflict_origin_device_fkey
    foreign key (origin_device) references account_device (anonymous_id) on delete set null;
create index on wardrobe_item_conflict (origin_device);

-- -------------------------------------------------------------- updated_at

-- Nothing maintained these, so they depended on every future writer
-- remembering. change_seq is the sync cursor, so a stale updated_at breaks no
-- correctness — it just lies, which is worse than being absent.
create function set_updated_at() returns trigger language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger set_updated_at before update on account
    for each row execute function set_updated_at();
create trigger set_updated_at before update on wardrobe_item
    for each row execute function set_updated_at();
create trigger set_updated_at before update on active_challenge
    for each row execute function set_updated_at();
create trigger set_updated_at before update on challenge_completion
    for each row execute function set_updated_at();
create trigger set_updated_at before update on wear_record
    for each row execute function set_updated_at();
create trigger set_updated_at before update on job
    for each row execute function set_updated_at();

-- A photo's content is immutable (§20.1), so this column could only ever
-- report the time of a change that never happens.
alter table photo drop column updated_at;
