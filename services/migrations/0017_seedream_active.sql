-- Seedream 5.0 pro leads both image capabilities; 4.5 is the fallback. 0014
-- picked a different model for templates, and illustration led with 4.5 so
-- 5.0 pro only ever appeared after an escalation.
update ai_model_config
   set active_model = 'bytedance-seed/seedream-5-0-pro',
       alternate_model = 'bytedance-seed/seedream-4.5',
       updated_by = 'migration',
       updated_at = now()
 where capability = 'outfit_template';

-- The illustration row was never seeded, so a fresh database had no
-- configuration for a capability the worker depends on.
insert into ai_model_config (
    capability, model_class, active_model, alternate_model, prompt_version, updated_by
)
values (
    'illustration', 'image', 'bytedance-seed/seedream-5-0-pro', 'bytedance-seed/seedream-4.5',
    'p1', 'migration'
)
on conflict (capability) do update
   set active_model = excluded.active_model,
       alternate_model = excluded.alternate_model,
       updated_by = excluded.updated_by,
       updated_at = now();
