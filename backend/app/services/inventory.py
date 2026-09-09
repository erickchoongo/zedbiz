from dataclasses import dataclass
from decimal import Decimal
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models.enums import InventoryMovementType
from app.models.inventory_movement import InventoryMovement
from app.models.product import Product
from app.models.user import User
from app.schemas.product import (
    ProductCreateRequest,
    ProductUpdateRequest,
    StockAddRequest,
    StockAdjustRequest,
    StockReductionRequest,
)
from app.services.commercial import add_audit


@dataclass(frozen=True)
class ProductPage:
    items: list[Product]
    total: int


@dataclass(frozen=True)
class MovementWithActor:
    movement: InventoryMovement
    actor_name: str | None


@dataclass(frozen=True)
class MovementPage:
    items: list[MovementWithActor]
    total: int


@dataclass(frozen=True)
class InventoryTotals:
    total_active_products: int
    low_stock_count: int
    out_of_stock_count: int


class InventoryService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def create_product(self, business_id: UUID, request: ProductCreateRequest, actor: User) -> Product:
        product = Product(
            business_id=business_id,
            name=request.name,
            sku=request.sku,
            barcode=request.barcode,
            description=request.description,
            cost_price=request.cost_price,
            selling_price=request.selling_price,
            stock_quantity=request.opening_stock if request.track_inventory else Decimal("0.000"),
            low_stock_threshold=request.low_stock_threshold if request.track_inventory else Decimal("0.000"),
            track_inventory=request.track_inventory,
        )
        self.db.add(product)
        try:
            self.db.flush()
            if product.track_inventory and product.stock_quantity > 0:
                self.db.add(
                    InventoryMovement(
                        business_id=business_id,
                        product_id=product.id,
                        movement_type=InventoryMovementType.OPENING_STOCK,
                        quantity_before=Decimal("0.000"),
                        quantity_delta=product.stock_quantity,
                        quantity_after=product.stock_quantity,
                        unit_cost=product.cost_price,
                        reason="Opening stock",
                        performed_by_user_id=actor.id,
                        client_operation_id=request.client_operation_id,
                    )
                )
            self.db.commit()
            self.db.refresh(product)
        except IntegrityError as exc:
            self.db.rollback()
            raise HTTPException(status_code=409, detail="SKU, barcode, or operation ID already exists for this business") from exc
        except Exception:
            self.db.rollback()
            raise
        return product

    def summary(self, business_id: UUID) -> InventoryTotals:
        base = [Product.business_id == business_id, Product.is_active.is_(True)]
        total = self.db.scalar(select(func.count()).select_from(Product).where(*base)) or 0
        tracked = [*base, Product.track_inventory.is_(True)]
        low = self.db.scalar(
            select(func.count()).select_from(Product).where(
                *tracked, Product.stock_quantity <= Product.low_stock_threshold
            )
        ) or 0
        out = self.db.scalar(
            select(func.count()).select_from(Product).where(*tracked, Product.stock_quantity == 0)
        ) or 0
        return InventoryTotals(int(total), int(low), int(out))

    def list_products(
        self,
        business_id: UUID,
        *,
        page: int,
        page_size: int,
        search: str | None,
        is_active: bool | None,
        low_stock: bool | None,
        track_inventory: bool | None,
    ) -> ProductPage:
        filters = [Product.business_id == business_id]
        if search:
            pattern = f"%{search.strip()}%"
            filters.append(
                or_(Product.name.ilike(pattern), Product.sku.ilike(pattern), Product.barcode.ilike(pattern))
            )
        if is_active is not None:
            filters.append(Product.is_active.is_(is_active))
        if track_inventory is not None:
            filters.append(Product.track_inventory.is_(track_inventory))
        if low_stock is True:
            filters.extend(
                [
                    Product.is_active.is_(True),
                    Product.track_inventory.is_(True),
                    Product.stock_quantity <= Product.low_stock_threshold,
                ]
            )
        elif low_stock is False:
            filters.append(
                or_(
                    Product.is_active.is_(False),
                    Product.track_inventory.is_(False),
                    Product.stock_quantity > Product.low_stock_threshold,
                )
            )
        total = self.db.scalar(select(func.count()).select_from(Product).where(*filters)) or 0
        items = self.db.scalars(
            select(Product)
            .where(*filters)
            .order_by(Product.name, Product.id)
            .offset((page - 1) * page_size)
            .limit(page_size)
        ).all()
        return ProductPage(items=list(items), total=total)

    def update_product(self, product: Product, request: ProductUpdateRequest) -> Product:
        values = request.model_dump(exclude_unset=True)
        if not product.track_inventory and values.get("low_stock_threshold", Decimal("0")) != Decimal("0"):
            raise HTTPException(status_code=409, detail="Services cannot have a low-stock threshold")
        for field, value in values.items():
            setattr(product, field, value)
        try:
            self.db.commit()
            self.db.refresh(product)
        except IntegrityError as exc:
            self.db.rollback()
            raise HTTPException(status_code=409, detail="SKU or barcode already exists for this business") from exc
        except Exception:
            self.db.rollback()
            raise
        return product

    def set_active(self, product: Product, active: bool, actor: User) -> Product:
        if product.is_active == active:
            return product
        product.is_active = active
        add_audit(
            self.db,
            actor_user_id=actor.id,
            business_id=product.business_id,
            action="product.reactivated" if active else "product.deactivated",
            entity_type="product",
            entity_id=product.id,
            metadata={},
        )
        try:
            self.db.commit()
            self.db.refresh(product)
        except Exception:
            self.db.rollback()
            raise
        return product

    def add_stock(self, product_id: UUID, business_id: UUID, request: StockAddRequest, actor: User) -> InventoryMovement:
        return self._mutate(
            product_id=product_id,
            business_id=business_id,
            movement_type=InventoryMovementType.STOCK_ADDED,
            operation_id=request.client_operation_id,
            actor=actor,
            requested_quantity=request.quantity,
            target_quantity=None,
            unit_cost=request.unit_cost,
            reason=request.reason,
        )

    def adjust_stock(self, product_id: UUID, business_id: UUID, request: StockAdjustRequest, actor: User) -> InventoryMovement:
        return self._mutate(
            product_id=product_id,
            business_id=business_id,
            movement_type=InventoryMovementType.MANUAL_ADJUSTMENT,
            operation_id=request.client_operation_id,
            actor=actor,
            requested_quantity=None,
            target_quantity=request.target_quantity,
            unit_cost=None,
            reason=request.reason,
        )

    def reduce_stock(
        self,
        product_id: UUID,
        business_id: UUID,
        request: StockReductionRequest,
        actor: User,
        movement_type: InventoryMovementType,
    ) -> InventoryMovement:
        if movement_type not in {InventoryMovementType.DAMAGED, InventoryMovementType.LOST}:
            raise ValueError("Unsupported stock reduction type")
        return self._mutate(
            product_id=product_id,
            business_id=business_id,
            movement_type=movement_type,
            operation_id=request.client_operation_id,
            actor=actor,
            requested_quantity=request.quantity,
            target_quantity=None,
            unit_cost=None,
            reason=request.reason,
        )

    def _mutate(
        self,
        *,
        product_id: UUID,
        business_id: UUID,
        movement_type: InventoryMovementType,
        operation_id: UUID,
        actor: User,
        requested_quantity: Decimal | None,
        target_quantity: Decimal | None,
        unit_cost: Decimal | None,
        reason: str | None,
    ) -> InventoryMovement:
        existing = self.db.scalar(
            select(InventoryMovement).where(
                InventoryMovement.business_id == business_id,
                InventoryMovement.client_operation_id == operation_id,
            )
        )
        if existing is not None:
            self._validate_retry(
                existing, product_id, movement_type, requested_quantity, target_quantity, unit_cost, reason
            )
            return existing

        product = self.db.scalar(
            select(Product)
            .where(Product.id == product_id, Product.business_id == business_id)
            .with_for_update()
        )
        if product is None:
            raise HTTPException(status_code=404, detail="Product not found")
        if not product.is_active:
            raise HTTPException(status_code=409, detail="Inactive products cannot receive stock changes")
        if not product.track_inventory:
            raise HTTPException(status_code=409, detail="Inventory tracking is disabled for this product")

        before = product.stock_quantity
        if movement_type == InventoryMovementType.STOCK_ADDED:
            assert requested_quantity is not None
            delta = requested_quantity
            after = before + delta
        elif movement_type == InventoryMovementType.MANUAL_ADJUSTMENT:
            assert target_quantity is not None
            after = target_quantity
            delta = after - before
            if delta == 0:
                raise HTTPException(status_code=409, detail="Target quantity already matches current stock")
        else:
            assert requested_quantity is not None
            delta = -requested_quantity
            after = before + delta
        if after < 0:
            raise HTTPException(status_code=409, detail="Stock operation would result in negative inventory")

        movement = InventoryMovement(
            business_id=business_id,
            product_id=product.id,
            movement_type=movement_type,
            quantity_before=before,
            quantity_delta=delta,
            quantity_after=after,
            unit_cost=unit_cost,
            reason=reason,
            performed_by_user_id=actor.id,
            client_operation_id=operation_id,
        )
        product.stock_quantity = after
        self.db.add(movement)
        try:
            self.db.commit()
            self.db.refresh(movement)
        except IntegrityError as exc:
            self.db.rollback()
            concurrent = self.db.scalar(
                select(InventoryMovement).where(
                    InventoryMovement.business_id == business_id,
                    InventoryMovement.client_operation_id == operation_id,
                )
            )
            if concurrent is not None:
                self._validate_retry(
                    concurrent, product_id, movement_type, requested_quantity, target_quantity, unit_cost, reason
                )
                return concurrent
            raise HTTPException(status_code=409, detail="Inventory operation conflicted with another update") from exc
        except Exception:
            self.db.rollback()
            raise
        return movement

    @staticmethod
    def _validate_retry(
        existing: InventoryMovement,
        product_id: UUID,
        movement_type: InventoryMovementType,
        requested_quantity: Decimal | None,
        target_quantity: Decimal | None,
        unit_cost: Decimal | None,
        reason: str | None,
    ) -> None:
        valid = existing.product_id == product_id and existing.movement_type == movement_type
        if movement_type == InventoryMovementType.STOCK_ADDED:
            valid = valid and existing.quantity_delta == requested_quantity and existing.unit_cost == unit_cost
        elif movement_type == InventoryMovementType.MANUAL_ADJUSTMENT:
            valid = valid and existing.quantity_after == target_quantity
        else:
            valid = valid and existing.quantity_delta == -(requested_quantity or Decimal("0"))
        valid = valid and existing.reason == reason
        if not valid:
            raise HTTPException(status_code=409, detail="Client operation ID was already used for a different operation")

    def movement_history(
        self,
        product_id: UUID,
        business_id: UUID,
        *,
        page: int,
        page_size: int,
        movement_type: InventoryMovementType | None,
    ) -> MovementPage:
        filters = [
            InventoryMovement.product_id == product_id,
            InventoryMovement.business_id == business_id,
        ]
        if movement_type:
            filters.append(InventoryMovement.movement_type == movement_type)
        total = self.db.scalar(
            select(func.count()).select_from(InventoryMovement).where(*filters)
        ) or 0
        rows = self.db.execute(
            select(InventoryMovement, User.full_name)
            .join(User, User.id == InventoryMovement.performed_by_user_id)
            .where(*filters)
            .order_by(InventoryMovement.created_at.desc(), InventoryMovement.id.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        ).all()
        return MovementPage(
            items=[MovementWithActor(movement=row[0], actor_name=row[1]) for row in rows],
            total=total,
        )
