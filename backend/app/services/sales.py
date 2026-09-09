import hashlib
import json
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP
from uuid import UUID, uuid5

from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.core.time import ensure_utc, utc_now
from app.models.business import Business
from app.models.customer import Customer
from app.models.debt import Debt
from app.models.enums import DebtStatus, InventoryMovementType, PaymentMethod, SaleStatus
from app.models.inventory_movement import InventoryMovement
from app.models.product import Product
from app.models.sale import Sale
from app.models.sale_counter import SaleCounter
from app.models.sale_item import SaleItem
from app.models.user import User
from app.schemas.sale import ReceiptItemResponse, ReceiptResponse, SaleCreateRequest, SaleVoidRequest
from app.services.commercial import add_audit

MONEY = Decimal("0.01")
QUANTITY = Decimal("0.001")


@dataclass(frozen=True)
class SaleWithPeople:
    sale: Sale
    sold_by_name: str | None
    voided_by_name: str | None = None


@dataclass(frozen=True)
class SalePage:
    items: list[SaleWithPeople]
    total: int


class SalesService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def create(self, business_id: UUID, request: SaleCreateRequest, actor: User) -> SaleWithPeople:
        quantities = self._aggregate(request)
        fingerprint = self._fingerprint(request, quantities)
        existing = self._by_operation(business_id, request.client_operation_id)
        if existing is not None:
            self._validate_sale_retry(existing, fingerprint)
            return SaleWithPeople(existing, actor.full_name if existing.sold_by_user_id == actor.id else existing.sold_by.full_name)

        customer: Customer | None = None
        if request.payment_method == PaymentMethod.CUSTOMER_DEBT:
            customer = self.db.scalar(
                select(Customer)
                .where(Customer.id == request.customer_id, Customer.business_id == business_id)
                .with_for_update()
            )
            if customer is None:
                raise HTTPException(status_code=404, detail="Customer not found")
            if not customer.is_active:
                raise HTTPException(status_code=409, detail="Customer is inactive")

        product_ids = sorted(quantities, key=str)
        products = self.db.scalars(
            select(Product)
            .where(Product.business_id == business_id, Product.id.in_(product_ids))
            .order_by(Product.id)
            .with_for_update()
        ).all()
        by_id = {product.id: product for product in products}
        if len(by_id) != len(product_ids):
            raise HTTPException(status_code=404, detail="One or more products were not found")

        for item in request.items:
            if item.sale_version is not None and item.sale_version != by_id[item.product_id].sale_version:
                raise HTTPException(status_code=409, detail="Product price or sale settings changed. This sale needs review.")

        subtotal = Decimal("0.00")
        total_cost = Decimal("0.00")
        line_values: list[tuple[Product, Decimal, Decimal, Decimal]] = []
        for product_id in product_ids:
            product = by_id[product_id]
            quantity = quantities[product_id]
            if not product.is_active:
                raise HTTPException(status_code=409, detail=f"{product.name} is inactive")
            if product.track_inventory and product.stock_quantity < quantity:
                raise HTTPException(status_code=409, detail=f"Insufficient stock for {product.name}")
            line_subtotal = (product.selling_price * quantity).quantize(MONEY, rounding=ROUND_HALF_UP)
            line_cost = (product.cost_price * quantity).quantize(MONEY, rounding=ROUND_HALF_UP)
            subtotal += line_subtotal
            total_cost += line_cost
            line_values.append((product, quantity, line_subtotal, line_cost))
        subtotal = subtotal.quantize(MONEY)
        total_cost = total_cost.quantize(MONEY)
        if request.discount_amount > subtotal:
            raise HTTPException(status_code=409, detail="Discount cannot exceed subtotal")
        total_amount = (subtotal - request.discount_amount).quantize(MONEY)
        if request.payment_method == PaymentMethod.CUSTOMER_DEBT and total_amount == 0:
            raise HTTPException(status_code=409, detail="A customer-credit sale must have an amount owing")
        gross_profit = (total_amount - total_cost).quantize(MONEY)
        sold_at = utc_now()
        sale = Sale(
            business_id=business_id,
            sale_number=self._next_number(business_id, sold_at),
            status=SaleStatus.COMPLETED,
            subtotal=subtotal,
            discount_amount=request.discount_amount,
            total_amount=total_amount,
            total_cost=total_cost,
            gross_profit=gross_profit,
            payment_method=request.payment_method,
            payment_reference=request.payment_reference,
            notes=request.notes,
            customer_id=customer.id if customer is not None else None,
            client_operation_id=request.client_operation_id,
            request_fingerprint=fingerprint,
            sold_by_user_id=actor.id,
            sold_at=sold_at,
        )
        self.db.add(sale)
        try:
            self.db.flush()
            for product, quantity, line_subtotal, line_cost in line_values:
                self.db.add(
                    SaleItem(
                        sale_id=sale.id,
                        business_id=business_id,
                        product_id=product.id,
                        product_name_snapshot=product.name,
                        sku_snapshot=product.sku,
                        track_inventory_snapshot=product.track_inventory,
                        quantity=quantity,
                        unit_selling_price=product.selling_price,
                        unit_cost=product.cost_price,
                        line_subtotal=line_subtotal,
                        line_cost=line_cost,
                        line_profit=(line_subtotal - line_cost).quantize(MONEY),
                    )
                )
                if product.track_inventory:
                    before = product.stock_quantity
                    after = before - quantity
                    product.stock_quantity = after
                    self.db.add(
                        InventoryMovement(
                            business_id=business_id,
                            product_id=product.id,
                            movement_type=InventoryMovementType.SALE,
                            quantity_before=before,
                            quantity_delta=-quantity,
                            quantity_after=after,
                            unit_cost=product.cost_price,
                            reference_type="SALE",
                            reference_id=sale.id,
                            reason=f"Sale {sale.sale_number}",
                            performed_by_user_id=actor.id,
                            client_operation_id=uuid5(request.client_operation_id, f"SALE:{product.id}"),
                        )
                    )
            if customer is not None:
                self.db.add(
                    Debt(
                        business_id=business_id,
                        customer_id=customer.id,
                        sale_id=sale.id,
                        original_amount=total_amount,
                        amount_paid=Decimal("0.00"),
                        outstanding_amount=total_amount,
                        status=DebtStatus.OPEN,
                        due_date=request.due_date,
                        created_by_user_id=actor.id,
                    )
                )
            self.db.flush()
            self.db.commit()
        except IntegrityError as exc:
            self.db.rollback()
            concurrent = self._by_operation(business_id, request.client_operation_id)
            if concurrent is not None:
                self._validate_sale_retry(concurrent, fingerprint)
                return SaleWithPeople(concurrent, concurrent.sold_by.full_name)
            raise HTTPException(status_code=409, detail="Sale conflicted with another transaction") from exc
        except Exception:
            self.db.rollback()
            raise
        result = self.get(business_id, sale.id)
        return result

    def get(self, business_id: UUID, sale_id: UUID) -> SaleWithPeople:
        sale = self.db.scalar(
            select(Sale)
            .options(
                selectinload(Sale.items), selectinload(Sale.sold_by), selectinload(Sale.voided_by),
                selectinload(Sale.customer), selectinload(Sale.debt),
            )
            .where(Sale.id == sale_id, Sale.business_id == business_id)
        )
        if sale is None:
            raise HTTPException(status_code=404, detail="Sale not found")
        return SaleWithPeople(sale, sale.sold_by.full_name, sale.voided_by.full_name if sale.voided_by else None)

    def list(
        self, business_id: UUID, *, page: int, page_size: int, search: str | None,
        payment_method: PaymentMethod | None, status: SaleStatus | None,
        date_from: datetime | None, date_to: datetime | None, sold_by_user_id: UUID | None,
    ) -> SalePage:
        filters = [Sale.business_id == business_id]
        if search:
            filters.append(Sale.sale_number.ilike(f"%{search.strip()}%"))
        if payment_method:
            filters.append(Sale.payment_method == payment_method)
        if status:
            filters.append(Sale.status == status)
        if date_from:
            filters.append(Sale.sold_at >= ensure_utc(date_from))
        if date_to:
            filters.append(Sale.sold_at <= ensure_utc(date_to))
        if sold_by_user_id:
            filters.append(Sale.sold_by_user_id == sold_by_user_id)
        total = self.db.scalar(select(func.count()).select_from(Sale).where(*filters)) or 0
        rows = self.db.execute(
            select(Sale, User.full_name)
            .join(User, User.id == Sale.sold_by_user_id)
            .where(*filters)
            .order_by(Sale.sold_at.desc(), Sale.id.desc())
            .offset((page - 1) * page_size).limit(page_size)
        ).all()
        return SalePage([SaleWithPeople(row[0], row[1]) for row in rows], total)

    def void(self, business_id: UUID, sale_id: UUID, request: SaleVoidRequest, actor: User) -> SaleWithPeople:
        operation_sale = self.db.scalar(
            select(Sale).where(Sale.business_id == business_id, Sale.void_client_operation_id == request.client_operation_id)
        )
        if operation_sale is not None:
            if operation_sale.id == sale_id and operation_sale.void_reason == request.reason:
                return self.get(business_id, sale_id)
            raise HTTPException(status_code=409, detail="Void operation ID was already used for a different request")
        sale = self.db.scalar(
            select(Sale)
            .options(selectinload(Sale.items))
            .where(Sale.id == sale_id, Sale.business_id == business_id)
            .with_for_update()
        )
        if sale is None:
            raise HTTPException(status_code=404, detail="Sale not found")
        if sale.status != SaleStatus.COMPLETED:
            raise HTTPException(status_code=409, detail="Sale has already been voided")
        linked_debt = self.db.scalar(
            select(Debt)
            .options(selectinload(Debt.payments))
            .where(Debt.sale_id == sale.id, Debt.business_id == business_id)
            .with_for_update()
        )
        if linked_debt is not None and (linked_debt.amount_paid > 0 or linked_debt.payments):
            raise HTTPException(
                status_code=409,
                detail="A customer-credit sale with repayments cannot be voided; use a future credit-note workflow",
            )
        tracked = {item.product_id: item for item in sale.items if item.track_inventory_snapshot}
        products = self.db.scalars(
            select(Product).where(Product.business_id == business_id, Product.id.in_(sorted(tracked, key=str))).order_by(Product.id).with_for_update()
        ).all() if tracked else []
        if len(products) != len(tracked):
            raise HTTPException(status_code=409, detail="A sale product is no longer available for stock restoration")
        now = utc_now()
        for product in products:
            item = tracked[product.id]
            before = product.stock_quantity
            after = before + item.quantity
            product.stock_quantity = after
            self.db.add(
                InventoryMovement(
                    business_id=business_id, product_id=product.id,
                    movement_type=InventoryMovementType.SALE_VOID,
                    quantity_before=before, quantity_delta=item.quantity, quantity_after=after,
                    unit_cost=item.unit_cost, reference_type="SALE", reference_id=sale.id,
                    reason=request.reason, performed_by_user_id=actor.id,
                    client_operation_id=uuid5(request.client_operation_id, f"SALE_VOID:{product.id}"),
                )
            )
        sale.status = SaleStatus.VOIDED
        sale.voided_at = now
        sale.voided_by_user_id = actor.id
        sale.void_reason = request.reason
        sale.void_client_operation_id = request.client_operation_id
        if linked_debt is not None:
            linked_debt.status = DebtStatus.VOIDED
            linked_debt.outstanding_amount = Decimal("0.00")
            linked_debt.voided_at = now
            linked_debt.voided_by_user_id = actor.id
            add_audit(
                self.db,
                actor_user_id=actor.id,
                business_id=business_id,
                action="debt.voided",
                entity_type="debt",
                entity_id=linked_debt.id,
                metadata={"sale_id": str(sale.id), "reason": request.reason},
            )
        add_audit(self.db, actor_user_id=actor.id, business_id=business_id, action="sale.voided",
                  entity_type="sale", entity_id=sale.id, metadata={"reason": request.reason})
        try:
            self.db.commit()
        except IntegrityError as exc:
            self.db.rollback()
            concurrent = self.db.scalar(select(Sale).where(Sale.business_id == business_id, Sale.void_client_operation_id == request.client_operation_id))
            if concurrent is not None and concurrent.id == sale_id and concurrent.void_reason == request.reason:
                return self.get(business_id, sale_id)
            raise HTTPException(status_code=409, detail="Void conflicted with another transaction") from exc
        except Exception:
            self.db.rollback()
            raise
        return self.get(business_id, sale_id)

    def receipt(self, business: Business, sale_id: UUID) -> ReceiptResponse:
        result = self.get(business.id, sale_id)
        sale = result.sale
        return ReceiptResponse(
            business_name=business.name, business_phone=business.phone_number,
            business_location=business.location, currency=business.currency,
            sale_number=sale.sale_number, status=sale.status, sold_at=sale.sold_at,
            seller_name=result.sold_by_name or "Team member",
            items=[ReceiptItemResponse(product_name=i.product_name_snapshot, sku=i.sku_snapshot,
                    quantity=i.quantity, unit_price=i.unit_selling_price, line_total=i.line_subtotal) for i in sale.items],
            subtotal=sale.subtotal, discount_amount=sale.discount_amount,
            total_amount=sale.total_amount, payment_method=sale.payment_method,
            payment_reference=sale.payment_reference,
            customer_name=sale.customer.name if sale.customer is not None else None,
            due_date=sale.debt.due_date if sale.debt is not None else None,
        )

    def _next_number(self, business_id: UUID, sold_at: datetime) -> str:
        counter = self.db.scalar(select(SaleCounter).where(SaleCounter.business_id == business_id).with_for_update())
        if counter is None:
            counter = SaleCounter(business_id=business_id, next_value=1)
            self.db.add(counter)
            self.db.flush()
        value = counter.next_value
        counter.next_value += 1
        return f"ZB-{sold_at:%Y%m%d}-{value:06d}"

    def _by_operation(self, business_id: UUID, operation_id: UUID) -> Sale | None:
        return self.db.scalar(
            select(Sale).options(
                selectinload(Sale.items), selectinload(Sale.sold_by), selectinload(Sale.voided_by),
                selectinload(Sale.customer), selectinload(Sale.debt),
            )
            .where(Sale.business_id == business_id, Sale.client_operation_id == operation_id)
        )

    @staticmethod
    def _aggregate(request: SaleCreateRequest) -> dict[UUID, Decimal]:
        values: dict[UUID, Decimal] = defaultdict(lambda: Decimal("0.000"))
        for item in request.items:
            values[item.product_id] += item.quantity
        return {key: value.quantize(QUANTITY) for key, value in values.items()}

    @staticmethod
    def _fingerprint(request: SaleCreateRequest, quantities: dict[UUID, Decimal]) -> str:
        payload = {
            "items": [[str(key), format(quantities[key], ".3f")] for key in sorted(quantities, key=str)],
            "payment_method": request.payment_method.value,
            "payment_reference": request.payment_reference,
            "discount_amount": format(request.discount_amount, ".2f"),
            "notes": request.notes,
            "customer_id": str(request.customer_id) if request.customer_id is not None else None,
            "due_date": request.due_date.isoformat() if request.due_date is not None else None,
        }
        # Omit entirely for older clients: their persisted fingerprints remain valid.
        versions = sorted({(str(item.product_id), item.sale_version) for item in request.items if item.sale_version is not None})
        if versions:
            payload["sale_versions"] = versions
        return hashlib.sha256(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()).hexdigest()

    @staticmethod
    def _validate_sale_retry(sale: Sale, fingerprint: str) -> None:
        if sale.request_fingerprint != fingerprint:
            raise HTTPException(status_code=409, detail="Client operation ID was already used for a different sale")
