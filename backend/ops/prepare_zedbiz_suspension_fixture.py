"""Prepare disposable live suspension-test accounts on the isolated local ZedBiz API.

Run from the ZedBiz backend directory:
    .venv/Scripts/python.exe ops/prepare_zedbiz_suspension_fixture.py

Only talks to 127.0.0.1:18001 and Docker's verified local suspension DB.
Does not run migrations, commit Git changes, or touch production services.
"""
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from uuid import uuid4

import psycopg

API = 'http://127.0.0.1:18001'
CONTAINER = 'zedbiz-suspension-test-db'
DB_NAME = 'zedbiz_suspension_test'


def local_db_config():
    container = json.loads(subprocess.check_output(['docker', 'inspect', CONTAINER], text=True))[0]
    env = dict(item.split('=', 1) for item in container['Config']['Env'] if '=' in item)
    binding = container['HostConfig']['PortBindings'].get('5432/tcp')
    if (container['Name'] != '/' + CONTAINER or env.get('POSTGRES_DB') != DB_NAME
            or binding != [{'HostIp': '127.0.0.1', 'HostPort': '55432'}]
            or not env.get('POSTGRES_USER') or not env.get('POSTGRES_PASSWORD')):
        raise RuntimeError('Refusing unexpected Docker container/database/port')
    return dict(host='127.0.0.1', port=55432, dbname=DB_NAME,
                user=env['POSTGRES_USER'], password=env['POSTGRES_PASSWORD'], connect_timeout=5)


def api_request(method, path, payload=None, token=None):
    if not path.startswith('/') or path.startswith('//'):
        raise RuntimeError('Unsafe API path')
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    body = json.dumps(payload).encode('utf-8') if payload is not None else None
    request = Request(API + path, data=body, headers=headers, method=method)
    try:
        with urlopen(request, timeout=12) as response:
            raw = response.read()
            return json.loads(raw) if raw else None
    except HTTPError as exc:
        # Avoid exposing credentials or bearer tokens from request headers.
        detail = exc.read(500).decode('utf-8', errors='replace')
        raise RuntimeError(f'Local API {method} {path} returned {exc.code}: {detail}') from exc


def main():
    connection = local_db_config()
    with psycopg.connect(**connection, options='-c default_transaction_read_only=on') as db:
        if db.execute('SELECT current_database()').fetchone()[0] != DB_NAME:
            raise RuntimeError('Wrong database; refusing fixture preparation')
        if db.execute('SELECT version_num FROM alembic_version').fetchall() != [('20261019_0008',)]:
            raise RuntimeError('Required suspension migration is missing')
    openapi = api_request('GET', '/openapi.json')
    paths = openapi.get('paths', {})
    if '/api/v1/admin/access/businesses/{business_id}/suspend' not in paths:
        raise RuntimeError('The server on port 18001 is not the expected suspension backend')

    suffix = uuid4().hex[:12]
    password = secrets.token_urlsafe(24) + 'Aa1!'
    admin_email = f'suspension-admin-{suffix}@example.com'
    owner_email = f'suspension-owner-{suffix}@example.com'
    admin = api_request('POST', '/api/v1/auth/register', {
        'email': admin_email, 'full_name': 'Local Suspension Admin', 'password': password,
    })
    owner = api_request('POST', '/api/v1/auth/register', {
        'email': owner_email, 'full_name': 'Local Suspension Owner', 'password': password,
    })
    for role, tokens in [('admin', admin), ('owner', owner)]:
        if not isinstance(tokens, dict) or not tokens.get('access_token') or not tokens.get('refresh_token'):
            raise RuntimeError(f'{role} registration did not return tokens')

    # Grant platform-admin status ONLY to the newly created local test identity.
    with psycopg.connect(**connection) as db:
        with db.transaction():
            result = db.execute('UPDATE users SET is_platform_admin = TRUE WHERE email = %s RETURNING id',
                                (admin_email,)).fetchall()
            if len(result) != 1:
                raise RuntimeError('Could not promote exactly one new local test admin')

    business = api_request('POST', '/api/v1/businesses',
                           {'name': f'Local Suspension Shop {suffix}'}, owner['access_token'])
    owner_profile = api_request('GET', '/api/v1/auth/me', token=owner['access_token'])
    api_request('GET', '/api/v1/admin/access/users', token=admin['access_token'])
    if not business.get('id') or not owner_profile.get('id'):
        raise RuntimeError('Fixture accounts/business not verified')
    fixture = {
        'base_url': API,
        'created_at': datetime.now(timezone.utc).isoformat(),
        'owner_login': {'email': owner_email, 'password': password},
        'admin': {'access_token': admin['access_token'], 'refresh_token': admin['refresh_token']},
        'owner': {'access_token': owner['access_token'], 'refresh_token': owner['refresh_token']},
        'business': {'id': business['id'], 'name': business['name']},
        'owner_id': owner_profile['id'],
    }
    # Save outside Git checkout: fixture includes bearer credentials.
    destination = Path(tempfile.gettempdir()) / f'zedbiz-suspension-fixture-{suffix}.json'
    with destination.open('x', encoding='utf-8') as handle:
        json.dump(fixture, handle, indent=2)
    try:
        os.chmod(destination, 0o600)
    except OSError:
        pass
    print('Isolated local test fixture prepared successfully.')
    print('Fixture path:', destination)
    print('Business:', business['name'])
    print('Do not commit or share the fixture JSON; it contains temporary access tokens.')
    print('PowerShell command to set the fixture:')
    print('$env:ZEDBIZ_SUSPENSION_FIXTURE = ' + "'" + str(destination) + "'")


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, URLError, psycopg.Error, subprocess.CalledProcessError) as exc:
        raise SystemExit(f'Fixture preparation stopped safely: {exc}')
