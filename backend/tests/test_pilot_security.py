import json
import secrets
from unittest.mock import Mock

import httpx
import pytest
from pydantic import ValidationError
from sqlalchemy.exc import OperationalError

from app.core.config import Settings
from app.core.readiness import check_database, expected_heads
from app.core.request_policy import WindowLimiter
from app.db.session import get_db
from app.main import create_app


def production(**changes):
    return Settings(_env_file=None, **dict(dict(app_env='production', jwt_secret=secrets.token_urlsafe(32),
        database_url='postgresql+psycopg://zedbiz_app:'+secrets.token_urlsafe(32)+'@db/zedbiz',
        cors_origins=['https://app.example.com'], trusted_hosts=['api.example.com', '127.0.0.1']), **changes))


@pytest.mark.parametrize('changes', [
    {'jwt_secret': ''}, {'jwt_secret': 'x'*64}, {'jwt_secret': 'replace-with-independent-random-jwt-secret'},
    {'cors_origins': ['*']}, {'cors_origins': ['http://app.example.com']}, {'trusted_hosts': ['*']},
    {'rate_limit_enabled': False}, {'web_concurrency': 2}, {'access_token_expire_minutes': 120},
    {'database_url': 'postgresql+psycopg://postgres:password@db/zedbiz'},
])
def test_production_rejects_unsafe_configuration(changes):
    with pytest.raises(ValidationError):
        production(**changes)


def test_production_valid_and_missing_secret(monkeypatch):
    assert production().web_concurrency == 1
    monkeypatch.delenv('JWT_SECRET', raising=False)
    with pytest.raises(ValidationError, match='JWT_SECRET'):
        Settings(_env_file=None, app_env='production')


def test_bounded_limiter_temporary_cooldown():
    clock = [0]
    limiter = WindowLimiter(60, capacity=1, clock=lambda: clock[0])
    assert limiter.allow('account', 2)[0]
    assert limiter.allow('account', 2)[0]
    assert not limiter.allow('account', 2)[0]
    assert not limiter.allow('other', 2)[0]
    clock[0] = 61
    assert limiter.allow('other', 2)[0]


def test_readiness_migration_and_role_checks():
    db = Mock()
    db.execute.return_value.scalars.return_value = ['old']
    with pytest.raises(RuntimeError, match='migration'):
        check_database(db, production=True)
    db.execute.return_value.scalars.return_value = list(expected_heads())
    db.execute.return_value.scalar_one.return_value = True
    with pytest.raises(RuntimeError, match='privileges'):
        check_database(db, production=True)


@pytest.mark.anyio
async def test_login_limits_general_limits_health_and_spoofed_forwarding():
    settings = Settings(_env_file=None, app_env='development', rate_limit_login=2, rate_limit_account=2,
                        rate_limit_api=4, trusted_hosts=['test'])
    app = create_app(settings)
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://test') as client:
        # Invalid payloads still consume the IP limit, before password hashing.
        for i in range(2):
            assert (await client.post('/api/v1/auth/login', json={}, headers={'X-Forwarded-For': f'1.2.3.{i}'})).status_code == 422
        limited = await client.post('/api/v1/auth/login', json={})
        assert limited.status_code == 429 and int(limited.headers['retry-after']) > 0
        await client.get('/api/v1/auth/me')
        assert (await client.get('/api/v1/auth/me')).status_code == 429
        assert (await client.get('/api/v1/health')).status_code == 200


@pytest.mark.anyio
async def test_account_limit_applies_across_ips_without_account_disclosure():
    app = create_app(Settings(_env_file=None, app_env='development', rate_limit_account=1))
    for i, expected in [(1, 422), (2, 429)]:
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app, client=(f'10.1.1.{i}', 20)), base_url='http://test') as client:
            response = await client.post('/api/v1/auth/login', json={'email':'nobody@example.com'})
            assert response.status_code == expected
            assert 'nobody' not in response.text


@pytest.mark.anyio
async def test_safe_errors_size_host_headers_and_cors(caplog):
    app = create_app(Settings(_env_file=None, app_env='test', trusted_hosts=['test'], cors_origins=['https://app.example.com']))
    @app.get('/failure')
    def failure():
        raise RuntimeError('secret-password SELECT * FROM private /server/path')
    @app.get('/db-failure')
    def db_failure():
        raise OperationalError('SQL secret', {}, Exception('database-password'))
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://test') as client:
        response = await client.get('/failure?token=private-token', headers={'Origin':'https://app.example.com'})
        assert response.status_code == 500
        assert response.headers['x-request-id'] == response.json()['request_id']
        assert response.headers['access-control-allow-origin'] == 'https://app.example.com'
        assert response.headers['x-content-type-options'] == 'nosniff'
        assert 'secret-password' not in response.text and 'SELECT' not in response.text
        assert (await client.get('/db-failure')).status_code == 503
        assert (await client.post('/api/v1/auth/login', content=b'x'*262145)).status_code == 413
        assert (await client.get('/api/v1/health', headers={'Host':'evil.test'})).status_code == 400
    assert 'private-token' not in caplog.text and 'database-password' not in caplog.text


@pytest.mark.anyio
async def test_production_startup_fails_without_ready_database(monkeypatch):
    app = create_app(production())
    engine = Mock()
    engine.connect.side_effect = OperationalError('private SQL', {}, Exception('secret'))
    monkeypatch.setattr('app.main.engine', engine)
    with pytest.raises(RuntimeError, match='readiness') as error:
        async with app.router.lifespan_context(app):
            pass
    assert 'secret' not in str(error.value)


@pytest.mark.anyio
async def test_extreme_sale_amount_rejected_before_inventory_mutation(client, db):
    from tests.test_sales import business, product, auth, sale_payload
    tokens,bid=await business(client,db,'bounded-sale@example.com')
    headers=auth(tokens['access_token'])
    item=await product(client,tokens['access_token'],bid,name='High value',sku='HIGH',cost='1.00',price='9999999999.00',stock='3.000')
    response=await client.post(f'/api/v1/businesses/{bid}/sales',headers=headers,json=sale_payload([(item['id'],'2.000')]))
    assert response.status_code==422
    response=await client.get(f"/api/v1/businesses/{bid}/products/{item['id']}",headers=headers)
    assert response.json()['stock_quantity']=='3.000'
