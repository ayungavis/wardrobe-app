-- FR-074 wants every inference attempt explainable from its own row. A refusal
-- classified as one word hid whether the provider said 401, 402, or 404; the
-- status code is classified data, never provider text, so it may be stored.
alter table ai_inference_attempt
    add column http_status integer check (http_status between 100 and 599);
