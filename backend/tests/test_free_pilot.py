import importlib.util
from pathlib import Path

import pytest
from pydantic import ValidationError
from sqlalchemy import create_engine
from sqlalchemy.engine import make_url

from app.core.config import Settings


@pytest.mark.parametrize('scheme', ['postgres', 'postgresql', 'postgresql+psycopg'])
def test_supabase_url_preserves_ssl_and_encoded_password(scheme):
    url = f'{scheme}://zedbiz_app.project:p%40ss%2Fword@aws-0-region.pooler.supabase.com:5432/postgres?sslmode=verify-full&sslrootcert=C%3A%2Fcerts%2Fca.crt'
    settings = Settings(_env_file=None, app_env='test', database_url=url, database_ssl_required=True)
    parsed = make_url(settings.database_url)
    assert parsed.drivername == 'postgresql+psycopg'
    assert parsed.password == 'p@ss/word'
    engine = create_engine(settings.database_url)
    _, kwargs = engine.dialect.create_connect_args(parsed)
    assert kwargs['sslmode'] == 'verify-full'
    assert kwargs['sslrootcert'] == 'C:/certs/ca.crt'
    assert kwargs['user'] == 'zedbiz_app.project'
    engine.dispose()


@pytest.mark.parametrize('mode', ['', '?sslmode=disable', '?sslmode=require', '?sslmode=verify-ca'])
def test_hosted_ssl_requires_certificate_and_hostname_verification(mode):
    with pytest.raises(ValidationError, match='verify-full'):
        Settings(_env_file=None, database_url='postgresql://app:secret@db/postgres'+mode, database_ssl_required=True)


def test_render_command_uses_port_and_forces_hosted_guards(monkeypatch):
    path = Path(__file__).resolve().parents[1]/'ops/start_render.py'
    spec = importlib.util.spec_from_file_location('start_render', path)
    entry = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(entry)
    # The entrypoint mutates its process environment; isolate it from other tests.
    monkeypatch.setattr(entry.os, 'environ', dict(entry.os.environ))
    for key in ('PORT','APP_ENV','REQUIRE_PRODUCTION','DATABASE_SSL_REQUIRED','GIT_COMMIT','RENDER_GIT_COMMIT'):
        monkeypatch.delenv(key, raising=False)
    with pytest.raises(RuntimeError, match='PORT'):
        entry.command()
    monkeypatch.setenv('PORT', '12345')
    monkeypatch.setenv('RENDER_GIT_COMMIT', 'a'*40)
    command = entry.command()
    assert command[command.index('--port')+1] == '12345'
    assert '--reload' not in command
    assert '--no-proxy-headers' in command
    import os
    assert os.environ['REQUIRE_PRODUCTION'] == 'true'
    assert os.environ['DATABASE_SSL_REQUIRED'] == 'true'
    assert os.environ['GIT_COMMIT'] == 'a'*40
