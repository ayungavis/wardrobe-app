-- §18 rule 4 (T41): consent to server storage, recorded at the first upload and
-- synchronised so a second device does not re-ask. A timestamp, not a boolean:
-- null already means "not yet", and the date is worth having.
alter table account_preference
    add column upload_consent_at timestamptz;
