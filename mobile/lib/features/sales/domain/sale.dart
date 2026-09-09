import 'package:zedbiz/features/commercial/domain/money.dart';
import 'package:zedbiz/features/debts/domain/debt.dart';
import 'package:zedbiz/features/products/domain/product.dart';

enum SaleStatus { completed, voided }

enum SalePaymentMethod {
  cash,
  mtnMoney,
  airtelMoney,
  zamtelMoney,
  bankTransfer,
  other,
  customerDebt,
}

String paymentApi(SalePaymentMethod value) => switch (value) {
  SalePaymentMethod.cash => 'CASH',
  SalePaymentMethod.mtnMoney => 'MTN_MONEY',
  SalePaymentMethod.airtelMoney => 'AIRTEL_MONEY',
  SalePaymentMethod.zamtelMoney => 'ZAMTEL_MONEY',
  SalePaymentMethod.bankTransfer => 'BANK_TRANSFER',
  SalePaymentMethod.other => 'OTHER',
  SalePaymentMethod.customerDebt => 'CUSTOMER_DEBT',
};
String paymentLabel(SalePaymentMethod value) => switch (value) {
  SalePaymentMethod.cash => 'Cash',
  SalePaymentMethod.mtnMoney => 'MTN Money',
  SalePaymentMethod.airtelMoney => 'Airtel Money',
  SalePaymentMethod.zamtelMoney => 'Zamtel Money',
  SalePaymentMethod.bankTransfer => 'Bank transfer',
  SalePaymentMethod.other => 'Other',
  SalePaymentMethod.customerDebt => 'Customer Credit',
};
SalePaymentMethod paymentFromApi(String value) =>
    SalePaymentMethod.values.firstWhere((item) => paymentApi(item) == value);

class SaleSummary {
  const SaleSummary({
    this.localSyncState,
    required this.id,
    required this.number,
    required this.status,
    required this.total,
    required this.paymentMethod,
    required this.soldAt,
    required this.seller,
    this.customerName,
    this.debtId,
  });
  factory SaleSummary.fromJson(Map<String, dynamic> json, String currency) =>
      SaleSummary(
        id: json['id'] as String,
        localSyncState: json['local_sync_state'] as String?,
        number: json['sale_number'] as String,
        status: (json['status'] as String) == 'VOIDED'
            ? SaleStatus.voided
            : SaleStatus.completed,
        total: Money.parse(json['total_amount'] as String, currency),
        paymentMethod: paymentFromApi(json['payment_method'] as String),
        soldAt: DateTime.parse(json['sold_at'] as String),
        seller: json['sold_by_name'] as String? ?? 'Team member',
        customerName: json['customer_name'] as String?,
        debtId: json['debt_id'] as String?,
      );
  final String? localSyncState;
  final String id, number, seller;
  final String? customerName, debtId;
  final SaleStatus status;
  final Money total;
  final SalePaymentMethod paymentMethod;
  final DateTime soldAt;
}

class SaleLine {
  const SaleLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.sku,
    this.unitCost,
    this.lineCost,
    this.lineProfit,
  });
  factory SaleLine.fromJson(Map<String, dynamic> json, String currency) =>
      SaleLine(
        name: json['product_name_snapshot'] as String,
        sku: json['sku_snapshot'] as String?,
        quantity: Quantity.parse(json['quantity'] as String),
        unitPrice: Money.parse(json['unit_selling_price'] as String, currency),
        lineTotal: Money.parse(json['line_subtotal'] as String, currency),
        unitCost: json['unit_cost'] == null
            ? null
            : Money.parse(json['unit_cost'] as String, currency),
        lineCost: json['line_cost'] == null
            ? null
            : Money.parse(json['line_cost'] as String, currency),
        lineProfit: json['line_profit'] == null
            ? null
            : Money.parse(json['line_profit'] as String, currency),
      );
  final String name;
  final String? sku;
  final Quantity quantity;
  final Money unitPrice, lineTotal;
  final Money? unitCost, lineCost, lineProfit;
}

class SaleDetail {
  const SaleDetail({
    this.localSyncState,
    required this.id,
    required this.number,
    required this.status,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.paymentMethod,
    required this.soldAt,
    required this.seller,
    required this.items,
    this.paymentReference,
    this.totalCost,
    this.grossProfit,
    this.voidReason,
    this.voidedBy,
    this.voidedAt,
    this.customerId,
    this.customerName,
    this.debtId,
    this.debtStatus,
    this.debtDueDate,
    this.debtOutstandingAmount,
  });
  factory SaleDetail.fromJson(Map<String, dynamic> json, String currency) =>
      SaleDetail(
        id: json['id'] as String,
        localSyncState: json['local_sync_state'] as String?,
        number: json['sale_number'] as String,
        status: (json['status'] as String) == 'VOIDED'
            ? SaleStatus.voided
            : SaleStatus.completed,
        subtotal: Money.parse(json['subtotal'] as String, currency),
        discount: Money.parse(json['discount_amount'] as String, currency),
        total: Money.parse(json['total_amount'] as String, currency),
        paymentMethod: paymentFromApi(json['payment_method'] as String),
        paymentReference: json['payment_reference'] as String?,
        soldAt: DateTime.parse(json['sold_at'] as String),
        seller: json['sold_by_name'] as String? ?? 'Team member',
        items: (json['items'] as List)
            .map((e) => SaleLine.fromJson(e as Map<String, dynamic>, currency))
            .toList(),
        totalCost: json['total_cost'] == null
            ? null
            : Money.parse(json['total_cost'] as String, currency),
        grossProfit: json['gross_profit'] == null
            ? null
            : Money.parse(json['gross_profit'] as String, currency),
        voidReason: json['void_reason'] as String?,
        voidedBy: json['voided_by_name'] as String?,
        voidedAt: json['voided_at'] == null
            ? null
            : DateTime.parse(json['voided_at'] as String),
        customerId: json['customer_id'] as String?,
        customerName: json['customer_name'] as String?,
        debtId: json['debt_id'] as String?,
        debtStatus: json['debt_status'] == null
            ? null
            : debtStatusFromApi(json['debt_status'] as String),
        debtDueDate: json['debt_due_date'] == null
            ? null
            : DateTime.parse(json['debt_due_date'] as String),
        debtOutstandingAmount: json['debt_outstanding_amount'] == null
            ? null
            : Money.parse(json['debt_outstanding_amount'] as String, currency),
      );
  final String? localSyncState;
  final String id, number, seller;
  final SaleStatus status;
  final Money subtotal, discount, total;
  final SalePaymentMethod paymentMethod;
  final String? paymentReference;
  final DateTime soldAt;
  final List<SaleLine> items;
  final Money? totalCost, grossProfit;
  final String? voidReason, voidedBy;
  final DateTime? voidedAt;
  final String? customerId, customerName, debtId;
  final DebtStatus? debtStatus;
  final DateTime? debtDueDate;
  final Money? debtOutstandingAmount;
}

class ReceiptData {
  const ReceiptData({
    this.localSyncState,
    required this.businessName,
    required this.currency,
    required this.saleNumber,
    required this.status,
    required this.soldAt,
    required this.seller,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.paymentMethod,
    this.phone,
    this.location,
    this.reference,
    this.customerName,
    this.dueDate,
  });
  factory ReceiptData.fromJson(Map<String, dynamic> json) => ReceiptData(
    businessName: json['business_name'] as String,
    localSyncState: json['local_sync_state'] as String?,
    currency: json['currency'] as String,
    phone: json['business_phone'] as String?,
    location: json['business_location'] as String?,
    saleNumber: json['sale_number'] as String,
    status: (json['status'] as String) == 'VOIDED'
        ? SaleStatus.voided
        : SaleStatus.completed,
    soldAt: DateTime.parse(json['sold_at'] as String),
    seller: json['seller_name'] as String,
    items: (json['items'] as List)
        .map(
          (e) => SaleLine(
            name: (e as Map<String, dynamic>)['product_name'] as String,
            sku: e['sku'] as String?,
            quantity: Quantity.parse(e['quantity'] as String),
            unitPrice: Money.parse(
              e['unit_price'] as String,
              json['currency'] as String,
            ),
            lineTotal: Money.parse(
              e['line_total'] as String,
              json['currency'] as String,
            ),
          ),
        )
        .toList(),
    subtotal: Money.parse(
      json['subtotal'] as String,
      json['currency'] as String,
    ),
    discount: Money.parse(
      json['discount_amount'] as String,
      json['currency'] as String,
    ),
    total: Money.parse(
      json['total_amount'] as String,
      json['currency'] as String,
    ),
    paymentMethod: paymentFromApi(json['payment_method'] as String),
    reference: json['payment_reference'] as String?,
    customerName: json['customer_name'] as String?,
    dueDate: json['due_date'] == null
        ? null
        : DateTime.parse(json['due_date'] as String),
  );
  final String? localSyncState;
  final String businessName, currency, saleNumber, seller;
  final String? phone, location, reference;
  final String? customerName;
  final SaleStatus status;
  final DateTime soldAt;
  final List<SaleLine> items;
  final Money subtotal, discount, total;
  final SalePaymentMethod paymentMethod;
  final DateTime? dueDate;
}
