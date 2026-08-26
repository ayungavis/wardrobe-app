-- FR-072 keeps model, prompt, and budget in the database so a template style can
-- change without a redeploy, the same way the illustration capability works.
alter table ai_model_config drop constraint ai_model_config_capability_check;
alter table ai_model_config add constraint ai_model_config_capability_check check (
    capability in (
        'challenge_text', 'item_attributes', 'recommendation_text', 'illustration',
        'outfit_template'
    )
);

alter table ai_inference_attempt drop constraint ai_inference_attempt_capability_check;
alter table ai_inference_attempt add constraint ai_inference_attempt_capability_check check (
    capability in (
        'challenge_text', 'item_attributes', 'recommendation_text', 'illustration',
        'outfit_template'
    )
);

alter table ai_usage_limit drop constraint ai_usage_limit_capability_check;
alter table ai_usage_limit add constraint ai_usage_limit_capability_check check (
    capability in (
        'challenge_text', 'item_attributes', 'recommendation_text', 'illustration',
        'outfit_template'
    )
);

-- 0002 pinned image generation to the illustration capability alone; templates
-- are the second one, and a text model here would still render nothing.
alter table ai_model_config drop constraint ai_model_config_check;
alter table ai_model_config add constraint ai_model_config_check check (
    (capability in ('illustration', 'outfit_template')) = (model_class = 'image')
);

insert into ai_model_config (
    capability, model_class, active_model, alternate_model, prompt_version, params, updated_by
)
values (
    'outfit_template', 'image', 'google/gemini-2.5-flash-image', 'bytedance-seed/seedream-5-0-pro',
    'v1',
    jsonb_build_object(
        'lookbook', 'Compose a fashion lookbook page on a plain background. Place the person photo '
            || 'upright in the centre at full height, and arrange the garment cut-outs around it in '
            || 'two columns. Under each garment print its name and the wear count exactly as given. '
            || 'Keep the person exactly as photographed: do not redraw, restyle, or replace the face.',
        'blisterGreen', 'Compose a toy blister pack on a pale green ridged card with a barcode at the '
            || 'top left and a hanging hole at the top centre. Put the title in a serif face under '
            || 'them. Seal each garment cut-out in its own small clear compartment down the left, and '
            || 'seal the person photo upright in one tall clear compartment on the right. Keep the '
            || 'person exactly as photographed: do not redraw, restyle, or replace the face.',
        'blisterCream', 'Compose a toy blister pack on a pale cream ridged card with a barcode at the '
            || 'top left and a hanging hole at the top centre. Put the title in a bold condensed '
            || 'all-caps face under them. Seal each garment cut-out in its own small clear '
            || 'compartment down the left, and seal the person photo upright in one tall clear '
            || 'compartment on the right. Keep the person exactly as photographed: do not redraw, '
            || 'restyle, or replace the face.',
        'resolution', '2K',
        'aspectRatio', '3:4'
    ),
    'migration'
);

insert into ai_usage_limit (id, scope, capability, window_seconds, max_requests, updated_by)
values ('019205f0-0000-7000-8000-000000000012', 'account', 'outfit_template', 3600, 20, 'migration');

-- One row per generation, append-only like item_illustration, so an older style
-- is never rewritten by a newer one and the feed can carry both.
create table completion_template (
    id              uuid primary key,
    account_id      uuid        not null references account (id) on delete cascade,
    completion_id   uuid        not null references challenge_completion (id) on delete cascade,
    media_object_id uuid        not null references media_object (id),
    template        text        not null check (template in ('lookbook', 'blisterGreen', 'blisterCream')),
    model           text        not null,
    prompt_version  text        not null,
    change_seq      bigint      not null,
    created_at      timestamptz not null default now(),
    deleted_at      timestamptz
);
create index on completion_template (account_id, change_seq);
create index on completion_template (completion_id);
create index on completion_template (media_object_id);
