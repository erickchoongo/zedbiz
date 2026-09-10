"""Disposable PostgreSQL suite, real HTTP races, pilot smoke, load and restore drill.

Credentials are read from the external development runtime environment. Nothing
is inserted into the working business database. Outputs contain counts/timings.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import secrets
import socket
import statistics
import subprocess
import sys
import tempfile
import threading
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
    parser.add_argument('--skip-suite', action='store_true')
    parser.add_argument('--suite-only', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=True)
    cfg = dict(line.split('=', 1) for line in args.runtime_env.read_text().splitlines() if '=' in line and not line.startswith('#'))
    name = 'zedbiz_test_'+uuid.uuid4().hex
    connection_args = dict(host='127.0.0.1', user=cfg['POSTGRES_USER'], password=cfg['POSTGRES_PASSWORD'], connect_timeout=10)
    results = {'database': name, 'concurrency': {}, 'performance_ms': {}}
    with psycopg.connect(**connection_args, dbname=cfg['POSTGRES_DB'], autocommit=True) as admin:
        admin.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(name)))
        server = None
        try:
            database_url = f"postgresql+psycopg://{cfg['POSTGRES_USER']}:{cfg['POSTGRES_PASSWORD']}@127.0.0.1:5432/{name}"
            env = dict(os.environ, DATABASE_URL=database_url, APP_ENV='test', JWT_SECRET=secrets.token_urlsafe(32), RATE_LIMIT_ENABLED='true')
            subprocess.run([sys.executable,'-m','alembic','upgrade','head'],cwd=root/'backend',env=env,check=True)
            if not args.skip_suite:
                subprocess.run([sys.executable,'-m','pytest','-q'],cwd=root/'backend',env=dict(env,ZEDBIZ_TEST_DATABASE_URL=database_url),check=True)
            if args.suite_only:
                return
            with socket.socket() as listener:
                listener.bind(('127.0.0.1',0)); port=listener.getsockname()[1]
            base_url=f'http://127.0.0.1:{port}'
            with (output/'m9-live-api.log').open('w') as log:
                server=subprocess.Popen([sys.executable,'-m','uvicorn','app.main:app','--host','127.0.0.1','--port',str(port),'--no-access-log'],cwd=root/'backend',env=env,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
                with httpx.Client(base_url=base_url,timeout=30) as api, psycopg.connect(**connection_args,dbname=name) as db:
                    for _ in range(100):
                        try:
                            if api.get('/api/v1/health').status_code==200: break
                        except httpx.HTTPError: pass
                        time.sleep(.1)
                    headers={}
                    def request(method,path,payload=None,expected=200,custom_headers=None):
                        response=api.request(method,'/api/v1'+path,json=payload,headers=custom_headers if custom_headers is not None else headers)
                        assert response.status_code==expected, (method,path,response.status_code,response.text[:400])
                        return response.json() if response.content else None
                    email=f'{uuid.uuid4().hex}@example.com'; password=secrets.token_urlsafe(24)
                    request('POST','/auth/register',{'full_name':'Pilot operator','email':email,'password':password},201)
                    tokens=request('POST','/auth/login',{'email':email,'password':password})
                    headers={'Authorization':'Bearer '+tokens['access_token']}
                    user=request('GET','/auth/me')['id']
                    bid=request('POST','/businesses',{'name':'Brown Mini Mart','location':'Lusaka'},201)['id']
                    base='/businesses/'+bid
                    # Deliberate disposable fixture activation. Production uses audited admin commands/UI.
                    plan=uuid.uuid4()
                    db.execute("INSERT INTO subscription_plans(id,name,code,currency,price,billing_period,grace_period_days,is_active,created_at,updated_at) VALUES (%s,'Founder','M9-PILOT','ZMW',79,'MONTHLY',7,true,now(),now())",(plan,))
                    db.execute("INSERT INTO subscriptions(id,business_id,plan_id,status,starts_at,current_period_start,current_period_end,grace_ends_at,created_at,updated_at) VALUES (%s,%s,%s,'ACTIVE',now(),now(),now()+interval '30 days',now()+interval '37 days',now(),now())",(uuid.uuid4(),bid,plan))
                    db.commit()
                    def product(label,stock,price='10.00',tracked=True):
                        return request('POST',base+'/products',{'name':label,'selling_price':price,'cost_price':'5.00','opening_stock':stock,'track_inventory':tracked},201)
                    coke=product('Coca-Cola','50.000'); bread=product('Bread','30.000'); service=product('Airtime service','0.000',tracked=False)
                    stress=product('Offline stock','100.000')
                    request('POST',base+f"/products/{bread['id']}/stock/add",{'client_operation_id':str(uuid.uuid4()),'quantity':'1.000','reason':'Pilot stock received'})
                    customer=request('POST',base+'/customers',{'name':'Pilot customer'},201)
                    def sale(pid,method='CASH',**extra):
                        return dict(client_operation_id=str(uuid.uuid4()),items=[{'product_id':pid,'quantity':'1.000'}],payment_method=method,**extra)
                    cash=request('POST',base+'/sales',sale(coke['id']),201)
                    request('POST',base+'/sales',sale(bread['id'],'MTN_MONEY'),201)
                    credit=request('POST',base+'/sales',sale(service['id'],'CUSTOMER_DEBT',customer_id=customer['id']),201)
                    debt=request('GET',base+'/debts')['items'][0]
                    repayment={'client_operation_id':str(uuid.uuid4()),'amount':'2.50','payment_method':'CASH'}
                    first=request('POST',base+f"/debts/{debt['id']}/payments",repayment,201)
                    retry=request('POST',base+f"/debts/{debt['id']}/payments",repayment,201)
                    assert first['payment']['id']==retry['payment']['id']
                    def expense():
                        return {'client_operation_id':str(uuid.uuid4()),'category':'TRANSPORT','description':'Pilot delivery','amount':'2.50','expense_date':datetime.now(timezone.utc).date().isoformat(),'payment_method':'CASH'}
                    exp=request('POST',base+'/expenses',expense(),201)
                    def race(path,payloads):
                        barrier=threading.Barrier(2)
                        def worker(payload):
                            with httpx.Client(base_url=base_url,timeout=30) as concurrent:
                                barrier.wait()
                                return concurrent.post('/api/v1'+path,json=payload,headers=headers)
                        with ThreadPoolExecutor(max_workers=2) as pool:
                            return list(pool.map(worker,payloads))
                    last=product('Last item','1.000')
                    responses=race(base+'/sales',[sale(last['id']),sale(last['id'])])
                    assert sorted(r.status_code for r in responses)==[201,409]
                    results['concurrency']['last_stock']=[r.status_code for r in responses]
                    replay=product('Replay last item','1.000'); payload=sale(replay['id'])
                    responses=race(base+'/sales',[payload,payload])
                    assert [r.status_code for r in responses]==[201,201],[(r.status_code,r.text) for r in responses]
                    assert responses[0].json()['id']==responses[1].json()['id']
                    results['concurrency']['same_sale']=[201,201]
                    payload=expense(); responses=race(base+'/expenses',[payload,payload])
                    assert [r.status_code for r in responses]==[201,201]
                    assert responses[0].json()['id']==responses[1].json()['id']
                    results['concurrency']['same_expense']=[201,201]
                    pay=lambda: {'client_operation_id':str(uuid.uuid4()),'amount':'5.00','payment_method':'CASH'}
                    responses=race(base+f"/debts/{debt['id']}/payments",[pay(),pay()])
                    assert sorted(r.status_code for r in responses)==[201,409]
                    results['concurrency']['repayment_balance']=[r.status_code for r in responses]
                    finalpay={'client_operation_id':str(uuid.uuid4()),'amount':'2.50','payment_method':'CASH'}
                    responses=race(base+f"/debts/{debt['id']}/payments",[finalpay,finalpay])
                    assert [r.status_code for r in responses]==[201,201]
                    assert responses[0].json()['payment']['id']==responses[1].json()['payment']['id']
                    results['concurrency']['same_settlement']=[201,201]
                    assert request('GET',base+f"/debts/{debt['id']}")['outstanding_amount']=='0.00'
                    request('POST',base+f"/sales/{cash['id']}/void",{'client_operation_id':str(uuid.uuid4()),'reason':'Pilot correction'})
                    request('POST',base+f"/expenses/{exp['id']}/void",{'client_operation_id':str(uuid.uuid4()),'reason':'Pilot correction'})
                    receipt=request('GET',base+f"/sales/{cash['id']}/receipt")
                    assert not any(word in json.dumps(receipt) for word in ('unit_cost','profit','password','notes'))
                    other=request('POST','/businesses',{'name':'Isolation control'},201)['id']
                    for collection,identifier in [('sales',cash['id']),('expenses',exp['id']),('customers',customer['id']),('debts',debt['id']),('products',coke['id'])]:
                        request('GET',f'/businesses/{other}/{collection}/{identifier}',expected=404)
                    request('GET','/admin/businesses',expected=403)
                    with tempfile.TemporaryDirectory(prefix='zedbiz-pilot-fixture-') as temp:
                        fixture=Path(temp)/'fixture.json'
                        fixture.write_text(json.dumps(dict(tokens,url=base_url,business_id=bid,user_id=user,product_id=stress['id'],output_directory=str(output))))
                        subprocess.run([args.flutter,'test','--no-pub','test/live_pilot_stress_test.dart'],cwd=root/'mobile',env=dict(os.environ,ZEDBIZ_LIVE_FIXTURE=str(fixture)),check=True)
                    assert db.execute('SELECT stock_quantity FROM products WHERE id=%s',(stress['id'],)).fetchone()[0]==80
                    for scenario in ('expired','removed','deactivated'):
                        if scenario=='removed':
                            db.execute("UPDATE business_memberships SET role='CASHIER' WHERE business_id=%s AND user_id=%s",(bid,user)); db.commit()
                        with tempfile.TemporaryDirectory(prefix='zedbiz-policy-') as temp:
                            fixture=Path(temp)/'fixture.json'
                            data=dict(tokens,url=base_url,business_id=bid,user_id=user,product_id=stress['id'],cache_file=str(Path(temp)/'queue.sqlite'),scenario=scenario,phase='capture')
                            fixture.write_text(json.dumps(data))
                            test_env=dict(os.environ,ZEDBIZ_LIVE_FIXTURE=str(fixture))
                            command=[args.flutter,'test','--no-pub','test/live_pilot_policy_test.dart']
                            subprocess.run(command,cwd=root/'mobile',env=test_env,check=True)
                            if scenario=='expired': db.execute("UPDATE subscriptions SET status='EXPIRED', starts_at=now()-interval '60 days', current_period_start=now()-interval '60 days', current_period_end=now()-interval '30 days', grace_ends_at=now()-interval '23 days' WHERE business_id=%s",(bid,))
                            elif scenario=='removed': db.execute('UPDATE business_memberships SET is_active=false WHERE business_id=%s AND user_id=%s',(bid,user))
                            else: db.execute('UPDATE products SET is_active=false WHERE id=%s',(stress['id'],))
                            db.commit()
                            data['phase']='sync'; fixture.write_text(json.dumps(data))
                            subprocess.run(command,cwd=root/'mobile',env=test_env,check=True)
                        db.execute("UPDATE subscriptions SET status='ACTIVE', starts_at=now(), current_period_start=now(), current_period_end=now()+interval '30 days', grace_ends_at=now()+interval '37 days' WHERE business_id=%s",(bid,))
                        db.execute("UPDATE business_memberships SET role='OWNER',is_active=true WHERE business_id=%s AND user_id=%s",(bid,user))
                        db.execute('UPDATE products SET is_active=true WHERE id=%s',(stress['id'],)); db.commit()
                    results['policy_rejections']=['expired subscription','removed cashier membership','deactivated product']
                    assert db.execute('SELECT stock_quantity FROM products WHERE id=%s',(stress['id'],)).fetchone()[0]==80
                    # Large, labelled disposable benchmark fixture; never production seed.
                    db.execute("INSERT INTO products(id,business_id,name,selling_price,cost_price,stock_quantity,low_stock_threshold,track_inventory,is_active,created_at,updated_at) SELECT gen_random_uuid(),%s,'Benchmark product '||g,10,5,100,1,true,true,now(),now() FROM generate_series(1,500) g",(bid,))
                    db.execute("INSERT INTO customers(id,business_id,name,is_active,created_at,updated_at) SELECT gen_random_uuid(),%s,'Benchmark customer '||g,true,now(),now() FROM generate_series(1,500) g",(bid,))
                    db.execute("INSERT INTO sales(id,business_id,sale_number,status,subtotal,discount_amount,total_amount,total_cost,gross_profit,payment_method,client_operation_id,request_fingerprint,sold_by_user_id,sold_at,created_at,updated_at) SELECT gen_random_uuid(),%s,'PERF-'||g,'COMPLETED',10,0,10,5,5,'CASH',gen_random_uuid(),repeat('0',64),%s,now(),now(),now() FROM generate_series(1,5000) g",(bid,user))
                    db.execute("INSERT INTO sale_items(id,sale_id,business_id,product_id,product_name_snapshot,track_inventory_snapshot,quantity,unit_selling_price,unit_cost,line_subtotal,line_cost,line_profit,created_at) SELECT gen_random_uuid(),id,business_id,%s,'Benchmark airtime',false,1,10,5,10,5,5,now() FROM sales WHERE business_id=%s AND sale_number LIKE 'PERF-%%'",(service['id'],bid))
                    db.execute("UPDATE sales SET payment_method='CUSTOMER_DEBT',customer_id=%s WHERE business_id=%s AND sale_number IN (SELECT 'PERF-'||g FROM generate_series(1,300) g)",(customer['id'],bid))
                    db.execute("INSERT INTO debts(id,business_id,customer_id,sale_id,original_amount,amount_paid,outstanding_amount,status,due_date,created_by_user_id,created_at,updated_at) SELECT gen_random_uuid(),business_id,customer_id,id,10,0,10,'OPEN',current_date+7,%s,now(),now() FROM sales WHERE business_id=%s AND sale_number LIKE 'PERF-%%' AND customer_id IS NOT NULL",(user,bid))
                    db.execute("INSERT INTO expenses(id,business_id,category,description,amount,payment_method,expense_date,client_operation_id,request_fingerprint,recorded_by_user_id,status,created_at,updated_at) SELECT gen_random_uuid(),%s,'TRANSPORT','Benchmark expense',2.50,'CASH',current_date,gen_random_uuid(),repeat('0',64),%s,'RECORDED',now(),now() FROM generate_series(1,1000) g",(bid,user))
                    db.commit()
                    for path in ['/dashboard?range=today','/reports/sales?range=today','/reports/expenses?range=today','/debts/summary','/products?page=1&page_size=100']:
                        durations=[]
                        for _ in range(5):
                            start=time.perf_counter(); request('GET',base+path); durations.append((time.perf_counter()-start)*1000)
                        results['performance_ms'][path]={'median':round(statistics.median(durations),2),'max':round(max(durations),2)}
                    assert db.execute('SELECT count(*) FROM products WHERE stock_quantity<0').fetchone()[0]==0
                    assert db.execute('SELECT count(*) FROM pg_constraint WHERE connamespace=\'public\'::regnamespace AND NOT convalidated').fetchone()[0]==0
                    results['indexes']=[r[0] for r in db.execute("SELECT indexname FROM pg_indexes WHERE schemaname='public' ORDER BY indexname")]
                    counts={table:db.execute(sql.SQL('SELECT count(*) FROM {}').format(sql.Identifier(table))).fetchone()[0] for table in ('users','businesses','products','inventory_movements','sales','sale_items','debts','debt_payments','expenses','audit_logs')}
                    results['counts']=counts
                    (output/'m9-expected-counts.json').write_text(json.dumps(counts))
                    db.commit()
            server.terminate(); server.wait(timeout=20); server=None
            backup_dir=output/'m9-backups'
            common=['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File']
            subprocess.run(common+[str(root/'scripts/backup-postgres.ps1'),'-EnvFile',str(args.runtime_env.resolve()),'-ComposeFile',str(root/'docker-compose.yml'),'-BackupDirectory',str(backup_dir),'-Database',name],check=True)
            backup=max(backup_dir.glob('*.dump'),key=lambda p:p.stat().st_mtime)
            restore='zedbiz_restore_'+uuid.uuid4().hex
            subprocess.run(common+[str(root/'scripts/restore-postgres.ps1'),'-EnvFile',str(args.runtime_env.resolve()),'-ComposeFile',str(root/'docker-compose.yml'),'-BackupFile',str(backup),'-RestoreDatabase',restore,'-ExpectedCountsFile',str(output/'m9-expected-counts.json'),'-RemoveAfterVerification'],check=True)
            results['backup']=backup.name; results['restore']='passed; expected counts matched; disposable restored database removed'
            (output/'m9-postgres-results.json').write_text(json.dumps(results,indent=2))
            print(json.dumps(results,indent=2))
        finally:
            if server:
                server.terminate(); server.wait(timeout=20)
            assert name.startswith('zedbiz_test_')
            admin.execute(sql.SQL('DROP DATABASE {}').format(sql.Identifier(name)))
            print('Disposable pilot database and temporary credential fixture removed.')


if __name__=='__main__':
    main()
