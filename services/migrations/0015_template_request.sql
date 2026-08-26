-- The editor asks for a template while the challenge is still active, so there
-- is no completion to hang the row on and the server holds none of the images
-- yet. The client mints the request id and uploads what it has.
alter table completion_template
    drop constraint completion_template_completion_id_fkey;
alter table completion_template
    rename column completion_id to request_id;
alter table completion_template rename to outfit_template;
