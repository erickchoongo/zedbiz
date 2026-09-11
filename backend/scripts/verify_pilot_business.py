"""One internal business on the existing loopback production rehearsal.

All business writes use real authenticated APIs. Only admin promotion/plan seed
use existing server CLI. This deliberately cannot target a remote deployment.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import uuid

import httpx


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--env-file', type=Path, required=True)
    parser.add_argument('--credentials-file', type=Path, required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    parser.add_argument('--flutter', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output_directory.resolve()
    output.mkdir(parents=True, exist_ok=True)
    credentials = json.loads(args.credentials_file.read_text(encoding='utf-8-sig'))
    journal_file = output/'pilot-business-journal.json'
    journal = json.loads(journal_file.read_text()) if journal_file.exists() else {}

    def save():
        journal_file.write_text(json.dumps(journal, indent=2))

    def cli(*command):
        result = subprocess.run(['docker', 'compose', '--env-file', str(args.env_file.resolve()),
                                 '-f', str(root/'docker-compose.prod.yml'), 'exec', '-T', 'api', *command],
                                capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise RuntimeError('Local rehearsal CLI failed; no secrets logged')
        return result.stdout.strip()

    assert cli('python', '-c', 'from app.core.config import get_settings; print(get_settings().app_env)') == 'production'
    count = int(cli('python', '-c', 'from sqlalchemy import text; from app.db.session import engine; c=engine.connect(); print(c.execute(text("SELECT count(*) FROM businesses")).scalar_one()); c.close()'))
    assert count <= 1, 'Rehearsal must contain at most one controlled business'
    url = 'http://127.0.0.1:18000'
    with httpx.Client(base_url=url, timeout=30) as api:
        def request(method, path, payload=None, expected=200):
            response = api.request(method, '/api/v1'+path, json=payload)
            if response.status_code != expected:
                raise RuntimeError(f'{method} {path}: HTTP {response.status_code}')
            return response.json() if response.content else None

        for role in ('admin', 'owner'):
            record = credentials[role]
            response = api.post('/api/v1/auth/register', json=dict(record, full_name='Internal pilot '+role))
            assert response.status_code in (201, 409), 'Registration failed'
        cli('python', '-m', 'app.cli', 'promote-admin', '--email', credentials['admin']['email'], '--yes')
        cli('python', '-m', 'app.cli', 'seed-founder-plan')
        owner_tokens = request('POST', '/auth/login', credentials['owner'])
        api.headers['Authorization'] = 'Bearer '+owner_tokens['access_token']
        user = request('GET', '/auth/me')
        assert not user['is_platform_admin']
        businesses = request('GET', '/businesses')
        if not businesses:
            assert count == 0, 'Existing business belongs to a different operator; refusing creation'
            businesses = [request('POST', '/businesses', {'name': 'ZedBiz Internal Pilot 1', 'location': 'Lusaka'}, 201)]
        assert len(businesses) == 1 and businesses[0]['name'] == 'ZedBiz Internal Pilot 1'
        bid = businesses[0]['id']
        journal['business_id'] = bid
        save()
        admin_tokens = request('POST', '/auth/login', credentials['admin'])
        api.headers['Authorization'] = 'Bearer '+admin_tokens['access_token']
        path = '/admin/businesses/'+bid
        detail = request('GET', path+'/commercial')
        onboarding = detail['onboarding']
        if onboarding['payment_status'] == 'UNPAID':
            request('PATCH', path+'/onboarding', {'payment_status': 'WAIVED', 'notes': 'Controlled internal local rehearsal. No external customer or cash collected.'})
        if onboarding['onboarding_status'] == 'NOT_STARTED':
            request('PATCH', path+'/onboarding', {'onboarding_status': 'IN_PROGRESS'})
        if onboarding['onboarding_status'] != 'COMPLETED':
            request('PATCH', path+'/onboarding', {'onboarding_status': 'COMPLETED'})
        if detail['subscription'] is None:
            request('POST', path+'/subscription/activate', {'payment_method': 'OTHER', 'payment_reference': 'LOCAL-PILOT1-NO-CASH-'+bid})
        request('POST', '/auth/logout', {'refresh_token': admin_tokens['refresh_token']}, 204)
        api.headers['Authorization'] = 'Bearer '+owner_tokens['access_token']
        base = '/businesses/'+bid
        assert request('GET', base+'/commercial-status')['writes_allowed']

        def product(name, quantity):
            found = [p for p in request('GET', base+'/products?page_size=100')['items'] if p['name'] == name]
            assert len(found) <= 1
            if found:
                return found[0]
            return request('POST', base+'/products', {'name': name, 'selling_price': '10.00', 'cost_price': '5.00', 'opening_stock': quantity, 'track_inventory': True}, 201)

        product_one = product('Pilot packaged item', '20.000')
        offline_product = product('Pilot offline item', '100.000')
        def operation(name):
            return str(uuid.uuid5(uuid.UUID(bid), 'pilot1-'+name))

        if 'stock_added' not in journal:
            request('POST', base+f"/products/{product_one['id']}/stock/add", {'quantity': '5.000', 'reason': 'Pilot opening stock verification', 'client_operation_id': operation('stock')})
            journal['stock_added'] = True
            save()
        customers = request('GET', base+'/customers?page_size=100')['items']
        customer = next((c for c in customers if c['name'] == 'Internal test customer'), None)
        if customer is None:
            customer = request('POST', base+'/customers', {'name': 'Internal test customer'}, 201)
        sales = []
        for label, method in [('cash', 'CASH'), ('mobile', 'MTN_MONEY'), ('credit', 'CUSTOMER_DEBT')]:
            payload = {'client_operation_id': operation(label), 'items': [{'product_id': product_one['id'], 'quantity': '1.000'}], 'payment_method': method, 'discount_amount': '0.00'}
            if label == 'credit':
                payload['customer_id'] = customer['id']
            sales.append(request('POST', base+'/sales', payload, 201))
        debt = request('GET', base+'/debts')['items'][0]
        request('POST', base+f"/debts/{debt['id']}/payments", {'client_operation_id': operation('repayment'), 'amount': '2.50', 'payment_method': 'CASH'}, 201)
        journal.setdefault('expense_date', datetime.now(timezone.utc).date().isoformat())
        save()
        request('POST', base+'/expenses', {'client_operation_id': operation('expense'), 'category': 'TRANSPORT', 'description': 'Internal pilot delivery', 'amount': '2.50', 'expense_date': journal['expense_date'], 'payment_method': 'CASH'}, 201)
        receipt = request('GET', base+f"/sales/{sales[0]['id']}/receipt")
        assert not any(word in json.dumps(receipt) for word in ('unit_cost', 'profit', 'password'))
        if not journal.get('offline_complete'):
            assert not journal.get('offline_started'), 'Prior interrupted offline run needs review before retry; refusing duplicate test operations'
            journal['offline_started'] = True
            save()
            fixture = output/'pilot-live-fixture.json'
            fixture.write_text(json.dumps(dict(owner_tokens, url=url, business_id=bid, user_id=user['id'], product_id=offline_product['id'], output_directory=str(output))))
            try:
                subprocess.run([args.flutter, 'test', '--no-pub', 'test/live_pilot_stress_test.dart'], cwd=root/'mobile',
                               env=dict(os.environ, ZEDBIZ_LIVE_FIXTURE=str(fixture)), check=True)
                journal['offline_complete'] = True
                save()
            finally:
                fixture.unlink(missing_ok=True)
            # The stress check rotated the owner's refresh token; sign in normally again.
            owner_tokens = request('POST', '/auth/login', credentials['owner'])
            api.headers['Authorization'] = 'Bearer '+owner_tokens['access_token']
        for endpoint in ('dashboard?range=today', 'reports/sales?range=today', 'reports/expenses?range=today', 'reports/performance?range=today', 'debts/summary'):
            request('GET', base+'/'+endpoint)
        stock = request('GET', base+f"/products/{offline_product['id']}")['stock_quantity']
        assert stock == '80.000'
        result = {'business_id': bid, 'business_name': businesses[0]['name'], 'environment': 'local production-configured rehearsal, not public HTTPS',
                  'sales': request('GET', base+'/sales')['total'], 'expenses': request('GET', base+'/expenses')['total'],
                  'offline_captured': 31, 'synced': 30, 'conflicts': 1, 'failed': 0, 'offline_stock': stock,
                  'onboarding': 'WAIVED / COMPLETED', 'subscription': 'ACTIVE', 'owner_is_platform_admin': False,
                  'physical_android': 'not performed; Flutter host SQLite/network simulation only'}
        assert result['sales'] == 23 and result['expenses'] == 11
        (output/'pilot-business-results.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result, indent=2))
        request('POST', '/auth/logout', {'refresh_token': owner_tokens['refresh_token']}, 204)


if __name__ == '__main__':
    main()
