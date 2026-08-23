-- The seed is pinned to an attempt alongside the model and prompt version
-- (FR-073): a retry must reproduce the same request, and moving to the
-- alternate model is a distinct attempt with its own pinned configuration.
alter table ai_inference_attempt add column seed bigint;
