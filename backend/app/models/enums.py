from enum import Enum


class MembershipRole(str, Enum):
    OWNER = "OWNER"
    MANAGER = "MANAGER"
    CASHIER = "CASHIER"


class BillingPeriod(str, Enum):
    MONTHLY = "MONTHLY"


class SubscriptionStatus(str, Enum):
    PENDING = "PENDING"
    ACTIVE = "ACTIVE"
    GRACE_PERIOD = "GRACE_PERIOD"
    EXPIRED = "EXPIRED"
    CANCELLED = "CANCELLED"


class PaymentMethod(str, Enum):
    MTN_MONEY = "MTN_MONEY"
    AIRTEL_MONEY = "AIRTEL_MONEY"
    ZAMTEL_MONEY = "ZAMTEL_MONEY"
    BANK_TRANSFER = "BANK_TRANSFER"
    CASH = "CASH"
    OTHER = "OTHER"
    CUSTOMER_DEBT = "CUSTOMER_DEBT"


class OnboardingPaymentStatus(str, Enum):
    UNPAID = "UNPAID"
    PAID = "PAID"
    WAIVED = "WAIVED"


class OnboardingStatus(str, Enum):
    NOT_STARTED = "NOT_STARTED"
    IN_PROGRESS = "IN_PROGRESS"
    COMPLETED = "COMPLETED"
    CANCELLED = "CANCELLED"


class InventoryMovementType(str, Enum):
    OPENING_STOCK = "OPENING_STOCK"
    STOCK_ADDED = "STOCK_ADDED"
    MANUAL_ADJUSTMENT = "MANUAL_ADJUSTMENT"
    DAMAGED = "DAMAGED"
    LOST = "LOST"
    SALE = "SALE"
    SALE_VOID = "SALE_VOID"


class SaleStatus(str, Enum):
    COMPLETED = "COMPLETED"
    VOIDED = "VOIDED"


class DebtStatus(str, Enum):
    OPEN = "OPEN"
    PARTIALLY_PAID = "PARTIALLY_PAID"
    PAID = "PAID"
    VOIDED = "VOIDED"


class ExpenseCategory(str, Enum):
    STOCK_PURCHASE = "STOCK_PURCHASE"
    RENT = "RENT"
    UTILITIES = "UTILITIES"
    TRANSPORT = "TRANSPORT"
    SALARIES_WAGES = "SALARIES_WAGES"
    AIRTIME_DATA = "AIRTIME_DATA"
    MARKETING = "MARKETING"
    MAINTENANCE = "MAINTENANCE"
    EQUIPMENT = "EQUIPMENT"
    FEES_CHARGES = "FEES_CHARGES"
    OTHER = "OTHER"


class ExpenseStatus(str, Enum):
    RECORDED = "RECORDED"
    VOIDED = "VOIDED"
