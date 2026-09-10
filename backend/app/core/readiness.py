"""Read-only startup/readiness checks. Migrations are a separate deployment step."""
from pathlib import Path

from alembic.config import Config
from alembic.script import ScriptDirectory
from sqlalchemy import text


def expected_heads():
    cfg = Config()
    cfg.set_main_option('script_location', str(Path(__file__).resolve().parents[2]/'migrations'))
    return set(ScriptDirectory.from_config(cfg).get_heads())


def check_database(connection, *, production=False):
    connection.execute(text('SELECT 1'))
    if production:
        heads = set(connection.execute(text('SELECT version_num FROM alembic_version')).scalars())
        if heads != expected_heads():
            raise RuntimeError('Database migration is not compatible with this application')
        unsafe = connection.execute(text('SELECT rolsuper OR rolcreatedb OR rolcreaterole OR rolbypassrls FROM pg_roles WHERE rolname = current_user')).scalar_one()
        if unsafe:
            raise RuntimeError('Application database role has administrative privileges')
