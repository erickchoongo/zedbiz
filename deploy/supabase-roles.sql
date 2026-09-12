-- Fresh, dedicated Supabase ZedBiz project; Data API must first be disabled.
-- Run as the project postgres administrator using psql, NOT the API app role.
-- No passwords in this file. Set each interactively with psql \password afterwards.
-- Refuse collisions rather than changing unrelated existing roles.
BEGIN;
CREATE ROLE zedbiz_migrator LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE zedbiz_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
-- Supabase postgres is a managed administrator, not a PostgreSQL superuser.
GRANT zedbiz_migrator TO postgres;
GRANT CONNECT ON DATABASE postgres TO zedbiz_migrator, zedbiz_app;
GRANT USAGE, CREATE ON SCHEMA public TO zedbiz_migrator;
GRANT USAGE ON SCHEMA public TO zedbiz_app;
ALTER DEFAULT PRIVILEGES FOR ROLE zedbiz_migrator IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO zedbiz_app;
ALTER DEFAULT PRIVILEGES FOR ROLE zedbiz_migrator IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO zedbiz_app;
-- GRANT can warn without failing when the operator lacks grant authority.
DO $$
BEGIN
    IF NOT has_schema_privilege('zedbiz_migrator', 'public', 'CREATE')
       OR NOT has_schema_privilege('zedbiz_migrator', 'public', 'USAGE')
       OR NOT has_schema_privilege('zedbiz_app', 'public', 'USAGE')
       OR has_schema_privilege('zedbiz_app', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'Unexpected public schema privileges; review managed project grants before proceeding';
    END IF;
END $$;
COMMIT;
-- Do not rerun on an existing configured project. Inspect existing roles first.
-- Migrations MUST use zedbiz_migrator so the default privileges apply.
-- Do not run the VPS bootstrap tool here: Supabase owns its schemas/admin roles.
