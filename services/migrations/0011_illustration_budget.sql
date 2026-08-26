-- FR-076 wants configurable request and cost limits enforced before a provider
-- call. The mechanism exists and is tested; no row ever filled it, so the
-- account-wide budget was unlimited. A user-triggered regeneration makes that a
-- spending decision, so the first row lands here rather than in an env var.
insert into ai_usage_limit (id, scope, capability, window_seconds, max_requests, updated_by)
values ('019205f0-0000-7000-8000-000000000010', 'account', 'illustration', 3600, 20, 'migration');
