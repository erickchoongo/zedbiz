from decimal import Decimal
from uuid import UUID, uuid4

import pytest
from sqlalchemy import func, select

from app.models.product import Product
from app.models.sale import Sale
from app.models.inventory_movement import InventoryMovement
from app.models.enums import InventoryMovementType
from app.models.subscription import Subscription
from app.models.enums import SubscriptionStatus
from tests.test_sales import business, product, auth

pytestmark = pytest.mark.anyio


async def test_product_token_price_conflict_and_retry_after_price_change(client, db):
    tokens, bid = await business(client, db, 'offline@example.com')
    token = tokens['access_token']
    p = await product(client, token, bid, name='Rice', sku='R', cost='10.00', price='79.99', stock='10.000')
    payload = {'client_operation_id': str(uuid4()), 'items': [
        {'product_id': p['id'], 'quantity': '1.250', 'sale_version': p['sale_version']}
    ], 'payment_method': 'CASH'}
    base = f'/api/v1/businesses/{bid}'
    accepted = await client.post(base+'/sales',headers=auth(token),json=payload)
    assert accepted.status_code == 201, accepted.text
    assert accepted.json()['total_amount'] == '99.99'
    model = db.get(Product, UUID(p['id']))
    model.selling_price = Decimal('120.00')
    db.commit()
    retry = await client.post(base+'/sales',headers=auth(token),json=payload)
    assert retry.status_code == 201
    assert retry.json()['id'] == accepted.json()['id']
    assert retry.json()['total_amount'] == '99.99'
    stale = {**payload, 'client_operation_id':str(uuid4())}
    rejected = await client.post(base+'/sales',headers=auth(token),json=stale)
    assert rejected.status_code == 409
    assert 'changed' in rejected.json()['detail']
    assert db.scalar(select(func.count()).select_from(Sale)) == 1
    assert db.scalar(select(func.count()).select_from(InventoryMovement).where(InventoryMovement.movement_type == InventoryMovementType.SALE)) == 1
    assert model.stock_quantity == Decimal('8.750')
    changed = {**payload, 'items':[{'product_id':p['id'],'quantity':'1.250','sale_version':model.sale_version}]}
    assert (await client.post(base+'/sales',headers=auth(token),json=changed)).status_code == 409


async def test_cosmetic_cost_changes_do_not_conflict_and_legacy_online_still_works(client, db):
    tokens, bid = await business(client, db, 'cosmetic@example.com')
    token=tokens['access_token']
    p=await product(client,token,bid,name='Soap',sku='S',cost='2.00',price='10.00',stock='10.000')
    model=db.get(Product,UUID(p['id']))
    model.name='Soap renamed'; model.description='New description'; model.cost_price=Decimal('4.00')
    db.commit()
    assert model.sale_version==p['sale_version']
    base=f'/api/v1/businesses/{bid}/sales'
    for versioned in [True,False]:
        item={'product_id':p['id'],'quantity':'1.000'}
        if versioned:item['sale_version']=p['sale_version']
        payload={'client_operation_id':str(uuid4()),'items':[item],'payment_method':'CASH'}
        response=await client.post(base,headers=auth(token),json=payload)
        assert response.status_code==201,response.text
        assert response.json()['total_cost']=='4.00'
        receipt=await client.get(base+'/'+response.json()['id']+'/receipt',headers=auth(token))
        assert 'cost' not in receipt.text and 'profit' not in receipt.text
    previous=model.sale_version
    model.is_active=False
    assert model.sale_version!=previous
    model.is_active=True; model.track_inventory=False
    assert model.sale_version!=previous


async def test_lost_response_can_reconcile_when_subscription_is_expired(client, db):
    tokens,bid=await business(client,db,'recover@example.com')
    headers=auth(tokens['access_token'])
    p=await product(client,tokens['access_token'],bid,name='Item',sku='I',cost='1.00',price='250.00',stock='10.000')
    base=f'/api/v1/businesses/{bid}'
    sale_payload={'client_operation_id':str(uuid4()),'items':[{'product_id':p['id'],'quantity':'1.000','sale_version':p['sale_version']}],'payment_method':'CASH'}
    expense_payload={'client_operation_id':str(uuid4()),'category':'TRANSPORT','description':'Delivery','amount':'79.99','expense_date':'2026-09-08','payment_method':'CASH'}
    accepted=[]
    for collection,payload in [('sales',sale_payload),('expenses',expense_payload)]:
        r=await client.post(base+'/'+collection,headers=headers,json=payload)
        assert r.status_code==201,r.text
        accepted.append(r.json()['id'])
    subscription=db.scalar(select(Subscription).where(Subscription.business_id==UUID(bid)))
    subscription.status=SubscriptionStatus.CANCELLED
    db.commit()
    for index,(collection,payload) in enumerate([('sales',sale_payload),('expenses',expense_payload)]):
        r=await client.post(base+'/'+collection+'/reconcile',headers=headers,json=payload)
        assert r.status_code==200,r.text
        assert r.json()['id']==accepted[index]
        missing={**payload,'client_operation_id':str(uuid4())}
        assert (await client.post(base+'/'+collection+'/reconcile',headers=headers,json=missing)).status_code==404
        assert (await client.post(base+'/'+collection,headers=headers,json=missing)).status_code==402
    assert (await client.get(base+'/sales/'+accepted[0]+'/receipt',headers=headers)).status_code==200
