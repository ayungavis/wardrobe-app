-- Server-side AI through OpenRouter (PRD §14.13, FR-072–FR-082).
--
-- The strongest privacy control in this file is what it does NOT contain: no
-- prompt column, no response column, no garment metadata. Storing user content
-- would take a migration, not a moment of carelessness (FR-074, §18.12).

-- FR-082: only providers whose terms forbid training on submitted content may
-- be routed to. The CHECK makes an unapproved provider unstorable rather than
-- merely discouraged.
create table ai_provider_allowlist (
    provider_slug    text primary key,
    forbids_training boolean     not null,
    retention_policy text        not null check (retention_policy in ('zero', 'short', 'other')),
    approved_by      text        not null,
    approved_at      timestamptz not null default now(),
    revoked_at       timestamptz,
    check (forbids_training)
);

-- FR-072: one active configuration per capability, enforced by the primary key
-- rather than by convention. Changing one capability cannot touch another.
create table ai_model_config (
    capability      text primary key check (
        capability in ('challenge_text', 'item_attributes', 'recommendation_text', 'illustration')
    ),
    model_class     text        not null check (model_class in ('text', 'image')),
    active_model    text        not null,
    alternate_model text,
    prompt_version  text        not null,
    params          jsonb       not null default '{}' check (jsonb_typeof(params) = 'object'),
    enabled         boolean     not null default true,
    updated_at      timestamptz not null default now(),
    updated_by      text        not null,
    -- Illustration is the only image capability, and it can never be anything
    -- else: a text model here would silently produce nothing renderable.
    check ((capability = 'illustration') = (model_class = 'image'))
);

create table ai_model_config_audit (
    id             uuid primary key,
    capability     text        not null,
    actor          text        not null,
    previous_value jsonb,
    new_value      jsonb       not null,
    changed_at     timestamptz not null default now()
);
create index on ai_model_config_audit (capability, changed_at desc);

-- FR-073/FR-074: one row per inference attempt, with the model and prompt
-- version pinned at claim time. Falling back to the alternate model is a new
-- attempt row, never an edit of this one, so past output stays explainable.
create table ai_inference_attempt (
    id             uuid primary key,
    -- Null for capabilities that are not per-account, such as curated-catalog
    -- generation.
    account_id     uuid references account (id) on delete cascade,
    job_id         uuid references job (id) on delete set null,
    capability     text        not null check (
        capability in ('challenge_text', 'item_attributes', 'recommendation_text', 'illustration')
    ),
    attempt_no     integer     not null check (attempt_no >= 1),
    model          text        not null,
    prompt_version text        not null,
    -- The effective OpenRouter/upstream route actually taken (FR-082).
    provider_route text,
    status         text        not null check (
        status in ('succeeded', 'failed', 'refused', 'invalid_output', 'skipped_limit')
    ),
    latency_ms     integer check (latency_ms >= 0),
    input_tokens   bigint check (input_tokens >= 0),
    output_tokens  bigint check (output_tokens >= 0),
    -- Null means the provider reported no accounting. FR-074 requires that be
    -- recorded as unavailable rather than estimated, which is what null says.
    cost_usd       numeric(12, 6) check (cost_usd >= 0),
    created_at     timestamptz not null default now()
);
-- Both indexes exist so FR-076 limits can be summed straight off this table;
-- a materialised counter is deferred until aggregation actually shows up in p95.
create index on ai_inference_attempt (capability, created_at desc);
create index on ai_inference_attempt (account_id, created_at desc);
create index on ai_inference_attempt (job_id);

-- FR-076: request, rate, and cost ceilings. A null capability means the row
-- applies to every capability in that scope.
create table ai_usage_limit (
    id             uuid primary key,
    scope          text        not null check (scope in ('global', 'account')),
    capability     text check (
        capability in ('challenge_text', 'item_attributes', 'recommendation_text', 'illustration')
    ),
    window_seconds integer     not null check (window_seconds > 0),
    max_requests   bigint check (max_requests > 0),
    max_cost_usd   numeric(12, 6) check (max_cost_usd > 0),
    enabled        boolean     not null default true,
    updated_at     timestamptz not null default now(),
    updated_by     text        not null,
    -- A limit that caps neither requests nor cost is not a limit.
    check (max_requests is not null or max_cost_usd is not null)
);
-- NULLS NOT DISTINCT so the catch-all row for a scope can exist only once.
create unique index on ai_usage_limit (scope, capability) nulls not distinct;
