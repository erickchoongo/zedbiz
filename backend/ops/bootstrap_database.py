"""Explicit administrative bootstrap. Never called by API startup."""
import os
import psycopg
from psycopg import sql
from sqlalchemy.engine import make_url


def main():
    admin, app, migrator = [make_url(os.environ[key]) for key in ('ADMIN_DATABASE_URL', 'DATABASE_URL', 'MIGRATION_DATABASE_URL')]
    if app.username != 'zedbiz_app' or migrator.username != 'zedbiz_migrator':
        raise RuntimeError('Use the dedicated zedbiz_app and zedbiz_migrator roles')
    if any(u.database != admin.database or u.host != admin.host for u in (app, migrator)):
        raise RuntimeError('All database URLs must target the same database/server')
    if any(not u.password or len(u.password) < 32 or len(set(u.password)) < 12 or 'replace-' in u.password for u in (admin, app, migrator)):
        raise RuntimeError('Generate independent strong database passwords before bootstrap')
    if len({u.password for u in (admin, app, migrator)}) != 3:
        raise RuntimeError('Database roles require independent passwords')
    with psycopg.connect(host=admin.host, port=admin.port or 5432, dbname=admin.database, user=admin.username, password=admin.password) as db:
        for role in (app, migrator):
            if not db.execute('SELECT 1 FROM pg_roles WHERE rolname=%s', (role.username,)).fetchone():
                db.execute(sql.SQL('CREATE ROLE {} LOGIN').format(sql.Identifier(role.username)))
            db.execute(sql.SQL('ALTER ROLE {} NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD {}').format(sql.Identifier(role.username), sql.Literal(role.password)))
        db.execute(sql.SQL('REVOKE ALL ON DATABASE {} FROM PUBLIC').format(sql.Identifier(admin.database)))
        db.execute(sql.SQL('GRANT CONNECT ON DATABASE {} TO zedbiz_app, zedbiz_migrator').format(sql.Identifier(admin.database)))
        db.execute('REVOKE ALL ON SCHEMA public FROM PUBLIC')
        db.execute('ALTER SCHEMA public OWNER TO zedbiz_migrator')
        db.execute('GRANT USAGE ON SCHEMA public TO zedbiz_app')
        db.execute('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO zedbiz_app')
        db.execute('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO zedbiz_app')
        db.execute('ALTER DEFAULT PRIVILEGES FOR ROLE zedbiz_migrator IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO zedbiz_app')
        db.execute('ALTER DEFAULT PRIVILEGES FOR ROLE zedbiz_migrator IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO zedbiz_app')
    print('Dedicated migration and restricted application roles configured. No secrets logged.')


if __name__ == '__main__':
    try:
        main()
    except Exception:
        raise SystemExit('Database bootstrap failed. Verify URL configuration and administrative access; secrets suppressed.')
