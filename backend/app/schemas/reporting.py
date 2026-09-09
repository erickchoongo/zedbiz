from datetime import date, datetime
from decimal import Decimal
from enum import Enum
from uuid import UUID

from pydantic import BaseModel, field_serializer

from app.models.enums import ExpenseCategory, PaymentMethod, SaleStatus


class ReportRange(str, Enum):
    TODAY = "today"
    YESTERDAY = "yesterday"
    WEEK = "week"
    MONTH = "month"


class PeriodResponse(BaseModel):
    range: str
    date_from: date
    date_to: date
    timezone: str


class RecentSaleResponse(BaseModel):
    id: UUID
    sale_number: str
    total_amount: Decimal
    payment_method: PaymentMethod
    sold_at: datetime
    status: SaleStatus

    @field_serializer("total_amount")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class RecentExpenseResponse(BaseModel):
    id: UUID
    description: str
    category: ExpenseCategory
    amount: Decimal
    expense_date: date
    payment_method: PaymentMethod

    @field_serializer("amount")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class DashboardResponse(BaseModel):
    business_id: UUID
    currency: str
    period: PeriodResponse
    gross_sales: Decimal
    sales_count: int
    gross_profit: Decimal | None
    total_expenses: Decimal | None
    net_operating_result: Decimal | None
    outstanding_customer_debt: Decimal | None
    overdue_customer_debt: Decimal | None
    low_stock_count: int
    out_of_stock_count: int
    recent_sales: list[RecentSaleResponse]
    recent_expenses: list[RecentExpenseResponse] | None

    @field_serializer(
        "gross_sales",
        "gross_profit",
        "total_expenses",
        "net_operating_result",
        "outstanding_customer_debt",
        "overdue_customer_debt",
    )
    def money_string(self, value: Decimal | None) -> str | None:
        return None if value is None else format(value, ".2f")


class PaymentBreakdownResponse(BaseModel):
    payment_method: PaymentMethod
    sales_count: int
    amount: Decimal

    @field_serializer("amount")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class DailySalesResponse(BaseModel):
    date: date
    sales_count: int
    amount: Decimal

    @field_serializer("amount")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class TopProductResponse(BaseModel):
    product_id: UUID
    product_name: str
    quantity: Decimal
    revenue: Decimal

    @field_serializer("quantity")
    def quantity_string(self, value: Decimal) -> str:
        return format(value, ".3f")

    @field_serializer("revenue")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class SalesReportResponse(BaseModel):
    business_id: UUID
    currency: str
    period: PeriodResponse
    gross_sales: Decimal
    sales_count: int
    average_sale_value: Decimal
    gross_profit: Decimal | None
    payment_breakdown: list[PaymentBreakdownResponse]
    sales_by_day: list[DailySalesResponse]
    top_products: list[TopProductResponse]

    @field_serializer("gross_sales", "average_sale_value", "gross_profit")
    def money_string(self, value: Decimal | None) -> str | None:
        return None if value is None else format(value, ".2f")


class CategoryBreakdownResponse(BaseModel):
    category: ExpenseCategory
    expense_count: int
    amount: Decimal

    @field_serializer("amount")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class ExpensePaymentBreakdownResponse(BaseModel):
    payment_method: PaymentMethod
    expense_count: int
    amount: Decimal

    @field_serializer("amount")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class DailyExpensesResponse(BaseModel):
    date: date
    expense_count: int
    amount: Decimal

    @field_serializer("amount")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class LargestExpenseResponse(BaseModel):
    id: UUID
    description: str
    category: ExpenseCategory
    amount: Decimal
    expense_date: date
    payment_method: PaymentMethod

    @field_serializer("amount")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class ExpensesReportResponse(BaseModel):
    business_id: UUID
    currency: str
    period: PeriodResponse
    total_expenses: Decimal
    expense_count: int
    category_breakdown: list[CategoryBreakdownResponse]
    payment_breakdown: list[ExpensePaymentBreakdownResponse]
    expenses_by_day: list[DailyExpensesResponse]
    largest_expenses: list[LargestExpenseResponse]

    @field_serializer("total_expenses")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")


class PerformanceReportResponse(BaseModel):
    business_id: UUID
    currency: str
    period: PeriodResponse
    gross_sales: Decimal
    gross_profit: Decimal
    expenses: Decimal
    net_operating_result: Decimal
    gross_margin_percentage: Decimal

    @field_serializer("gross_sales", "gross_profit", "expenses", "net_operating_result")
    def money_string(self, value: Decimal) -> str:
        return format(value, ".2f")

    @field_serializer("gross_margin_percentage")
    def percent_string(self, value: Decimal) -> str:
        return format(value, ".2f")
