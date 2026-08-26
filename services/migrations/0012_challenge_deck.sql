-- FR-006/FR-009/FR-080: a bounded deck of generated cards per user-local day,
-- and the derived, non-identifying context the generator is allowed to read.

alter table challenge_card
    -- The user-local day this card belongs to. Null for the curated catalog,
    -- which is dateless and global (FR-008).
    add column local_date     date,
    -- Slot within the day's deck. A retried generation lands on the same slots
    -- instead of doubling the deck.
    add column deck_index     smallint,
    add column title          text check (length(title) <= 60),
    -- The two garments the card dares you to combine. ON DELETE SET NULL so a
    -- removed item degrades the card rather than breaking it: a completion may
    -- already cite this row through card_id. Writing both-or-neither is the
    -- generator's rule, not the table's, because deleting one garment
    -- legitimately leaves the other behind; the deck endpoint reads a half pair
    -- as text-only (FR-010).
    add column top_item_id    uuid references wardrobe_item (id) on delete set null,
    add column bottom_item_id uuid references wardrobe_item (id) on delete set null,
    -- A generated card without a day is unreachable by the deck endpoint, and a
    -- dated curated card would leak one account's day into the global catalog.
    add constraint challenge_card_generated_has_a_day
        check ((source = 'generated') = (local_date is not null)),
    add constraint challenge_card_generated_has_a_slot
        check ((source = 'generated') = (deck_index is not null)),
    -- Generated copy always names the model that wrote it (FR-073); a heading is
    -- generated copy too.
    add constraint challenge_card_generated_has_a_title
        check (source = 'curated' or title is not null),
    -- FR-073 pins the prompt version as well as the model; the original CHECK
    -- only demanded the model.
    add constraint challenge_card_generated_names_its_prompt_version
        check (source = 'curated' or prompt_version is not null),
    -- ponytail: 10, not 5, because "how many cards appear each day" is still an
    -- open product question. The deck size lives in Rust; this only stops a
    -- runaway loop from filling the table.
    add constraint challenge_card_deck_index_range
        check (deck_index between 0 and 9);

-- The deck endpoint reads (account, day) in slot order and the enqueue asks
-- whether that pair exists. Uniqueness is what makes a retried generation
-- idempotent rather than a second deck; curated rows are all-null here and
-- NULLS DISTINCT keeps them out of it.
create unique index on challenge_card (account_id, local_date, deck_index);

-- ON DELETE SET NULL scans the child table: without these, deleting one item
-- reads every card in the database.
create index on challenge_card (top_item_id) where top_item_id is not null;
create index on challenge_card (bottom_item_id) where bottom_item_id is not null;

-- FR-080 permits derived, non-identifying context, and this is all of it: the
-- zone the device is in and the summary it computed from tomorrow's forecast.
-- No coordinates ever reach the server — the device resolves the forecast and
-- syncs the answer (§18.12).
alter table account_device
    add column time_zone          text check (length(time_zone) <= 64),
    add column locale             text check (length(locale) <= 16),
    add column weather_local_date date,
    -- A closed vocabulary, not the provider's forty conditions. Free text from a
    -- device is free text in a prompt, which FR-080 forbids.
    add column weather_condition  text check (weather_condition in (
        'clear', 'cloudy', 'rain', 'storm', 'snow', 'fog', 'wind', 'hot', 'cold'
    )),
    add column weather_high_c     smallint check (weather_high_c between -90 and 60),
    add column weather_low_c      smallint check (weather_low_c between -90 and 60),
    -- A forecast is only readable alongside the zone that dates it.
    add constraint account_device_weather_needs_a_zone
        check (weather_local_date is null or time_zone is not null);

-- The enqueue takes each account's most recently seen device that reported a
-- zone; the existing (account_id) index cannot serve that ordering.
create index on account_device (account_id, last_seen_at desc) where time_zone is not null;
