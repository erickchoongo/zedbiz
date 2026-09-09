from fastapi import APIRouter

from app.api.v1.routes.health import router as health_router
from app.api.v1.routes.auth import router as auth_router
from app.api.v1.routes.businesses import router as businesses_router
from app.api.v1.routes.commercial import router as commercial_router
from app.api.v1.routes.admin import router as admin_router
from app.api.v1.routes.products import router as products_router
from app.api.v1.routes.inventory import router as inventory_router
from app.api.v1.routes.sales import router as sales_router
from app.api.v1.routes.customers import router as customers_router
from app.api.v1.routes.debts import router as debts_router
from app.api.v1.routes.expenses import router as expenses_router
from app.api.v1.routes.reporting import router as reporting_router

api_router = APIRouter()
api_router.include_router(health_router, prefix="/health", tags=["health"])
api_router.include_router(auth_router, prefix="/auth", tags=["authentication"])
api_router.include_router(businesses_router, prefix="/businesses", tags=["businesses"])
api_router.include_router(commercial_router, prefix="/businesses", tags=["commercial"])
api_router.include_router(admin_router, prefix="/admin", tags=["admin"])
api_router.include_router(products_router, prefix="/businesses/{business_id}/products", tags=["products"])
api_router.include_router(inventory_router, prefix="/businesses/{business_id}/inventory", tags=["inventory"])
api_router.include_router(sales_router, prefix="/businesses/{business_id}/sales", tags=["sales"])
api_router.include_router(customers_router, prefix="/businesses/{business_id}/customers", tags=["customers"])
api_router.include_router(debts_router, prefix="/businesses/{business_id}/debts", tags=["customer credit"])
api_router.include_router(expenses_router, prefix="/businesses/{business_id}/expenses", tags=["expenses"])
api_router.include_router(reporting_router, prefix="/businesses/{business_id}", tags=["dashboard and reports"])
