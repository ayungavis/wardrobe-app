-- The curated catalog is global and the permanent fallback (FR-008). The ids
-- are fixed literals because the client ships a mock deck that references them
-- until a deck endpoint exists; a random id on either side breaks
-- challenge_completion's card_id foreign key on every completion.
insert into challenge_card (id, source, prompt_text, locale) values
    ('019205f0-0000-7000-8000-000000000001', 'curated', 'Freestyle', 'en'),
    ('019205f0-0000-7000-8000-000000000002', 'curated', 'Today is a good day to wear something red.', 'en'),
    ('019205f0-0000-7000-8000-000000000003', 'curated', 'Style your most comfortable shoes for going out.', 'en'),
    ('019205f0-0000-7000-8000-000000000004', 'curated', 'Layer two pieces you have never worn together.', 'en');
