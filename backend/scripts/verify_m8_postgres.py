"""Disposable PostgreSQL migrations + real Flutter/SQLite synchronization check."""
import argparse
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import tempfile
import time
import uuid

import httpx
import psycopg
from psycopg import sql


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runtime-env', type=Path, required=True)
    parser.add_argument('--flutter', required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    cfg = dict(line.split('=', 1) for line in args.runtime_env.read_text().splitlines() if '=' in line and not line.startswith('#'))
    name = 'zedbiz_test_' + uuid.uuid4().hex
    args.output_directory.mkdir(parents=True, exist_ok=True)
    with psycopg.connect(host='127.0.0.1', user=cfg['POSTGRES_USER'], password=cfg['POSTGRES_PASSWORD'], dbname=cfg['POSTGRES_DB'], autocommit=True) as admin:
        admin.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(name)))
        server = None
        try:
            with tempfile.TemporaryDirectory(prefix='zedbiz-m8-') as temp:
                with socket.socket() as listener:
                    listener.bind(('127.0.0.1', 0))
                    port = listener.getsockname()[1]
                url = f'http://127.0.0.1:{port}'
                env = dict(os.environ, DATABASE_URL=f"postgresql+psycopg://{cfg['POSTGRES_USER']}:{cfg['POSTGRES_PASSWORD']}@127.0.0.1:5432/{name}", JWT_SECRET=secrets.token_urlsafe(48), APP_ENV='test')
                subprocess.run([sys.executable, '-m', 'alembic', 'upgrade', 'head'], cwd=root/'backend', env=env, check=True)
                with (args.output_directory/'m8-live-api.log').open('w') as log:
                    server = subprocess.Popen([sys.executable, '-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', str(port)], cwd=root/'backend', env=env, stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
                    with httpx.Client(base_url=url, timeout=20) as api:
                        for _ in range(100):
                            try:
                                if api.get('/api/v1/health').status_code == 200: break
                            except httpx.HTTPError: pass
                            time.sleep(.1)
                        response = api.post('/api/v1/auth/register', json={'full_name':'Offline verification','email':f'{uuid.uuid4().hex}@example.com','password':secrets.token_urlsafe(30)})
                        response.raise_for_status()
                        tokens = response.json()
                        headers = {'Authorization':'Bearer '+tokens['access_token']}
                        user = api.get('/api/v1/auth/me', headers=headers).json()['id']
                        response = api.post('/api/v1/businesses', headers=headers, json={'name':'Offline verification shop','location':'Lusaka'})
                        response.raise_for_status()
                        bid = response.json()['id']
                        with psycopg.connect(host='127.0.0.1', user=cfg['POSTGRES_USER'], password=cfg['POSTGRES_PASSWORD'], dbname=name) as db:
                            plan = uuid.uuid4()
                            db.execute("INSERT INTO subscription_plans(id,name,code,currency,price,billing_period,grace_period_days,is_active,created_at,updated_at) VALUES (%s,'Test','LIVE-M8','ZMW',79,'MONTHLY',7,true,now(),now())", (plan,))
                            db.execute("INSERT INTO subscriptions(id,business_id,plan_id,status,starts_at,current_period_start,current_period_end,grace_ends_at,created_at,updated_at) VALUES (%s,%s,%s,'ACTIVE',now(),now(),now()+interval '30 days',now()+interval '37 days',now(),now())", (uuid.uuid4(),bid,plan))
                        response=api.post(f'/api/v1/businesses/{bid}/products',headers=headers,json={'name':'Rice','selling_price':'250.00','cost_price':'150.00','opening_stock':'10.000'})
                        response.raise_for_status()
                        pid=response.json()['id']
                        response=api.post(f'/api/v1/businesses/{bid}/customers',headers=headers,json={'name':'Test customer','phone_number':'+260970000001'})
                        response.raise_for_status()
                    fixture=Path(temp)/'fixture.json'
                    fixture.write_text(json.dumps({**tokens,'url':url,'business_id':bid,'user_id':user,'product_id':pid,'output_directory':str(args.output_directory)}))
                    test_env=dict(os.environ,ZEDBIZ_LIVE_FIXTURE=str(fixture))
                    subprocess.run([args.flutter,'test','--no-pub','test/live_offline_integration_test.dart'],cwd=root/'mobile',env=test_env,check=True)
                    print('Real PostgreSQL API + Flutter SQLite end-to-end verification passed.')
        finally:
            if server is not None:
                server.terminate()
                server.wait(timeout=20)
            assert name.startswith('zedbiz_test_')
            admin.execute(sql.SQL('DROP DATABASE {}').format(sql.Identifier(name)))
            print('Disposable PostgreSQL database and temporary credentials removed.')


if __name__ == '__main__':
    main()
