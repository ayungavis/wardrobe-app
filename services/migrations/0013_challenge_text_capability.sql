-- FR-080 becomes buildable: the text capability that words the daily deck, the
-- budget that caps it (FR-076), and enough curated rows that the fallback can
-- fill a whole deck (FR-008).

-- The weights are configuration, not constants, because FR-072 guarantees a
-- config change takes effect without a redeploy — and the right weighting for a
-- wardrobe is only knowable from use.
insert into ai_model_config
    (capability, model_class, active_model, alternate_model, prompt_version, params, updated_by)
values (
    'challenge_text', 'text',
    'google/gemini-2.5-flash-lite',
    'mistralai/mistral-nemo',
    'v1',
    '{"deckSize": 5,
      "weights": {"neglect": 1.0, "rarity": 0.6, "novelty": 0.9,
                  "weather": 1.2, "colour": 0.5, "renderable": 0.4, "reuse": 0.8}}'::jsonb,
    'migration'
)
on conflict (capability) do nothing;

-- One deck a day per account plus its retries, with room for a handful of manual
-- regenerations.
insert into ai_usage_limit (id, scope, capability, window_seconds, max_requests, updated_by)
values ('019205f0-0000-7000-8000-000000000011', 'account', 'challenge_text', 86400, 10, 'migration');

-- Freestyle (…0001) is a second completion path (FR-065), not a deck slot, so it
-- does not count toward the five a fallback deck needs.
insert into challenge_card (id, source, title, prompt_text, locale) values
    ('019205f0-0000-7000-8000-000000000005', 'curated', 'One colour only',
     'Build a whole outfit around a single colour.', 'en'),
    ('019205f0-0000-7000-8000-000000000006', 'curated', 'Back of the rail',
     'Wear the piece that has hung at the back the longest.', 'en'),
    ('019205f0-0000-7000-8000-000000000007', 'curated', 'Borrowed decade',
     'Dress like a decade you did not grow up in.', 'en'),
    ('019205f0-0000-7000-8000-000000000008', 'curated', 'Texture clash',
     'Put two very different fabrics in the same outfit.', 'en');

update challenge_card set title = 'Freestyle'    where id = '019205f0-0000-7000-8000-000000000001';
update challenge_card set title = 'Seeing red'   where id = '019205f0-0000-7000-8000-000000000002';
update challenge_card set title = 'Comfort out'  where id = '019205f0-0000-7000-8000-000000000003';
update challenge_card set title = 'Never paired' where id = '019205f0-0000-7000-8000-000000000004';
