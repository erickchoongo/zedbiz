"""Exercise an isolated, empty pilot Compose runtime. Never point at a live pilot."""
import argparse
import json
from pathlib import Path
import subprocess
import time
import httpx


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--env-file',required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[2]
    command=['docker','compose','--env-file',args.env_file,'-f',str(root/'docker-compose.prod.yml')]
    def compose(*parts,input=None,check=True):
        result=subprocess.run(command+list(parts),input=input,text=True,capture_output=True,check=check)
        return (result.stdout+result.stderr if parts[0]=='logs' else result.stdout).strip()
    # Refuse outage/migration simulations when this isolated rehearsal DB has business data.
    count=compose('exec','-T','db','psql','-U','zedbiz_admin','-d','zedbiz','-At','-c','SELECT count(*) FROM businesses')
    if count!='0':
        raise SystemExit('Runtime simulation requires an empty pilot database; existing businesses preserved.')
    results={}
    with httpx.Client(base_url='http://127.0.0.1:18000',timeout=15) as api:
        for _ in range(60):
            try:
                if api.get('/api/v1/health/ready').status_code==200: break
            except httpx.HTTPError: pass
            time.sleep(.5)
        else: raise AssertionError('Pilot API did not become ready')
        code="from app.db.session import engine\nfrom sqlalchemy import text\nwith engine.connect() as c:\n print(c.execute(text(\"SELECT current_user,has_schema_privilege(current_user,'public','CREATE')\")).one())\n"
        role=compose('exec','-T','api','python','-',input=code)
        assert 'zedbiz_app' in role and 'False' in role
        results['application_role']=role
        try:
            compose('stop','db')
            assert api.get('/api/v1/health').status_code==200
            response=api.get('/api/v1/health/ready')
            assert response.status_code==503 and 'postgresql' not in response.text
            results['database_outage']='liveness 200; readiness 503; no connection details'
        finally:
            compose('start','db')
        for _ in range(40):
            if api.get('/api/v1/health/ready').status_code==200: break
            time.sleep(.5)
        else: raise AssertionError('Database recovery did not restore readiness')
        head=compose('exec','-T','db','psql','-U','zedbiz_admin','-d','zedbiz','-At','-c','SELECT version_num FROM alembic_version')
        assert head.replace('_','').isalnum()
        try:
            compose('exec','-T','db','psql','-U','zedbiz_admin','-d','zedbiz','-c',"UPDATE alembic_version SET version_num='incompatible_pilot_check'")
            assert api.get('/api/v1/health/ready').status_code==503
            compose('restart','api')
            time.sleep(3)
            try:
                response=api.get('/api/v1/health')
                assert response.status_code!=200
            except httpx.HTTPError:
                pass
            for _ in range(30):
                logs=compose('logs','--tail','60','api')
                if 'Production database readiness check failed' in logs: break
                time.sleep(.5)
            else: raise AssertionError('Expected sanitized startup failure was not logged')
            results['schema_startup']='incompatible schema refused startup; sanitized failure'
        finally:
            compose('exec','-T','db','psql','-U','zedbiz_admin','-d','zedbiz','-c',f"UPDATE alembic_version SET version_num='{head}'")
            compose('restart','api')
        for _ in range(40):
            try:
                if api.get('/api/v1/health/ready').status_code==200: break
            except httpx.HTTPError: pass
            time.sleep(.5)
        else: raise AssertionError('API did not recover after schema restoration')
        results['recovered_readiness']=200
        # No real user is needed to verify account-safe temporary throttling.
        responses=[api.post('/api/v1/auth/login',json={'email':'nobody@example.com','password':'wrong-pilot-password'}) for _ in range(9)]
        assert [r.status_code for r in responses[:8]]==[401]*8
        assert responses[8].status_code==429
        results['production_login_limit']='eight generic failures, ninth 429'
        assert api.get('/api/v1/health',headers={'Host':'evil.example'}).status_code==400
        results['trusted_hosts']='foreign Host rejected 400'
    args.output.write_text(json.dumps(results,indent=2))
    print(json.dumps(results,indent=2))


if __name__=='__main__': main()
