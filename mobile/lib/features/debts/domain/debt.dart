import 'package:zedbiz/features/commercial/domain/money.dart';

enum DebtStatus { open, partiallyPaid, paid, voided }

DebtStatus debtStatusFromApi(String value) => switch (value) {
  'OPEN' => DebtStatus.open,
  'PARTIALLY_PAID' => DebtStatus.partiallyPaid,
  'PAID' => DebtStatus.paid,
  'VOIDED' => DebtStatus.voided,
  _ => throw FormatException('Unknown debt status: $value'),
};

String debtStatusApi(DebtStatus value) => switch (value) {
  DebtStatus.open => 'OPEN',
  DebtStatus.partiallyPaid => 'PARTIALLY_PAID',
  DebtStatus.paid => 'PAID',
  DebtStatus.voided => 'VOIDED',
};

String debtStatusLabel(DebtStatus value) => switch (value) {
  DebtStatus.open => 'OPEN',
  DebtStatus.partiallyPaid => 'PARTLY PAID',
  DebtStatus.paid => 'PAID',
  DebtStatus.voided => 'VOIDED',
};

enum DebtPaymentMethod {
  cash,
  mtnMoney,
  airtelMoney,
  zamtelMoney,
  bankTransfer,
  other,
}

String debtPaymentApi(DebtPaymentMethod value) => switch (value) {
  DebtPaymentMethod.cash => 'CASH',
  DebtPaymentMethod.mtnMoney => 'MTN_MONEY',
  DebtPaymentMethod.airtelMoney => 'AIRTEL_MONEY',
  DebtPaymentMethod.zamtelMoney => 'ZAMTEL_MONEY',
  DebtPaymentMethod.bankTransfer => 'BANK_TRANSFER',
  DebtPaymentMethod.other => 'OTHER',
};

String debtPaymentLabel(DebtPaymentMethod value) => switch (value) {
  DebtPaymentMethod.cash => 'Cash',
  DebtPaymentMethod.mtnMoney => 'MTN Money',
  DebtPaymentMethod.airtelMoney => 'Airtel Money',
  DebtPaymentMethod.zamtelMoney => 'Zamtel Money',
  DebtPaymentMethod.bankTransfer => 'Bank transfer',
  DebtPaymentMethod.other => 'Other',
};

DebtPaymentMethod debtPaymentFromApi(String value) => DebtPaymentMethod.values
    .firstWhere((method) => debtPaymentApi(method) == value);

class DebtSummary {
  const DebtSummary({
    required this.id,
    required this.businessId,
    required this.customerId,
    required this.customerName,
    required this.originalAmount,
    required this.amountPaid,
    required this.outstandingAmount,
    required this.status,
    required this.isOverdue,
    required this.createdAt,
    this.customerPhoneNumber,
    this.saleId,
    this.saleNumber,
    this.dueDate,
  });

  factory DebtSummary.fromJson(Map<String, dynamic> json, String currency) =>
      DebtSummary(
        id: json['id'] as String,
        businessId: json['business_id'] as String,
        customerId: json['customer_id'] as String,
        customerName: json['customer_name'] as String,
        customerPhoneNumber: json['customer_phone_number'] as String?,
        saleId: json['sale_id'] as String?,
        saleNumber: json['sale_number'] as String?,
        originalAmount: Money.parse(
          json['original_amount'] as String,
          currency,
        ),
        amountPaid: Money.parse(json['amount_paid'] as String, currency),
        outstandingAmount: Money.parse(
          json['outstanding_amount'] as String,
          currency,
        ),
        status: debtStatusFromApi(json['status'] as String),
        dueDate: _date(json['due_date']),
        isOverdue: json['is_overdue'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id, businessId, customerId, customerName;
  final String? customerPhoneNumber, saleId, saleNumber;
  final Money originalAmount, amountPaid, outstandingAmount;
  final DebtStatus status;
  final DateTime? dueDate;
  final bool isOverdue;
  final DateTime createdAt;

  bool get acceptsPayment =>
      status == DebtStatus.open || status == DebtStatus.partiallyPaid;
}

class DebtDetail extends DebtSummary {
  const DebtDetail({
    required super.id,
    required super.businessId,
    required super.customerId,
    required super.customerName,
    required super.originalAmount,
    required super.amountPaid,
    required super.outstandingAmount,
    required super.status,
    required super.isOverdue,
    required super.createdAt,
    required this.createdByUserId,
    super.customerPhoneNumber,
    super.saleId,
    super.saleNumber,
    super.dueDate,
    this.notes,
    this.createdByName,
    this.settledAt,
    this.voidedAt,
    this.updatedAt,
  });

  factory DebtDetail.fromJson(Map<String, dynamic> json, String currency) {
    final summary = DebtSummary.fromJson(json, currency);
    return DebtDetail(
      id: summary.id,
      businessId: summary.businessId,
      customerId: summary.customerId,
      customerName: summary.customerName,
      customerPhoneNumber: summary.customerPhoneNumber,
      saleId: summary.saleId,
      saleNumber: summary.saleNumber,
      originalAmount: summary.originalAmount,
      amountPaid: summary.amountPaid,
      outstandingAmount: summary.outstandingAmount,
      status: summary.status,
      dueDate: summary.dueDate,
      isOverdue: summary.isOverdue,
      createdAt: summary.createdAt,
      notes: json['notes'] as String?,
      createdByUserId: json['created_by_user_id'] as String,
      createdByName: json['created_by_name'] as String?,
      settledAt: _dateTime(json['settled_at']),
      voidedAt: _dateTime(json['voided_at']),
      updatedAt: _dateTime(json['updated_at']),
    );
  }

  final String? notes, createdByName;
  final String createdByUserId;
  final DateTime? settledAt, voidedAt, updatedAt;
}

class DebtPage {
  const DebtPage(this.items, this.page, this.pageSize, this.total);

  factory DebtPage.fromJson(Map<String, dynamic> json, String currency) =>
      DebtPage(
        (json['items'] as List<dynamic>)
            .map(
              (item) =>
                  DebtSummary.fromJson(item as Map<String, dynamic>, currency),
            )
            .toList(),
        json['page'] as int,
        json['page_size'] as int,
        json['total'] as int,
      );

  final List<DebtSummary> items;
  final int page, pageSize, total;
}

class DebtMetrics {
  const DebtMetrics({
    required this.totalOutstanding,
    required this.totalOverdue,
    required this.customersOwing,
    required this.openDebtCount,
  });

  factory DebtMetrics.fromJson(Map<String, dynamic> json, String currency) =>
      DebtMetrics(
        totalOutstanding: Money.parse(
          json['total_outstanding'] as String,
          currency,
        ),
        totalOverdue: Money.parse(json['total_overdue'] as String, currency),
        customersOwing: json['customers_owing'] as int,
        openDebtCount: json['open_debt_count'] as int,
      );

  final Money totalOutstanding, totalOverdue;
  final int customersOwing, openDebtCount;
}

class DebtPayment {
  const DebtPayment({
    required this.id,
    required this.businessId,
    required this.debtId,
    required this.customerId,
    required this.customerName,
    required this.amount,
    required this.paymentMethod,
    required this.receivedByUserId,
    required this.receivedByName,
    required this.paidAt,
    required this.createdAt,
    this.paymentReference,
    this.notes,
  });

  factory DebtPayment.fromJson(Map<String, dynamic> json, String currency) =>
      DebtPayment(
        id: json['id'] as String,
        businessId: json['business_id'] as String,
        debtId: json['debt_id'] as String,
        customerId: json['customer_id'] as String,
        customerName: json['customer_name'] as String,
        amount: Money.parse(json['amount'] as String, currency),
        paymentMethod: debtPaymentFromApi(json['payment_method'] as String),
        paymentReference: json['payment_reference'] as String?,
        receivedByUserId: json['received_by_user_id'] as String,
        receivedByName: json['received_by_name'] as String? ?? 'Team member',
        paidAt: DateTime.parse(json['paid_at'] as String),
        notes: json['notes'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String id, businessId, debtId, customerId, customerName;
  final String receivedByUserId, receivedByName;
  final Money amount;
  final DebtPaymentMethod paymentMethod;
  final String? paymentReference, notes;
  final DateTime paidAt, createdAt;
}

class DebtPaymentPage {
  const DebtPaymentPage(this.items, this.page, this.pageSize, this.total);

  factory DebtPaymentPage.fromJson(
    Map<String, dynamic> json,
    String currency,
  ) => DebtPaymentPage(
    (json['items'] as List<dynamic>)
        .map(
          (item) =>
              DebtPayment.fromJson(item as Map<String, dynamic>, currency),
        )
        .toList(),
    json['page'] as int,
    json['page_size'] as int,
    json['total'] as int,
  );

  final List<DebtPayment> items;
  final int page, pageSize, total;
}

class RepaymentResult {
  const RepaymentResult({required this.payment, required this.debt});

  factory RepaymentResult.fromJson(
    Map<String, dynamic> json,
    String currency,
  ) => RepaymentResult(
    payment: DebtPayment.fromJson(
      json['payment'] as Map<String, dynamic>,
      currency,
    ),
    debt: DebtDetail.fromJson(json['debt'] as Map<String, dynamic>, currency),
  );

  final DebtPayment payment;
  final DebtDetail debt;
}

class DebtReminder {
  const DebtReminder({
    required this.debtId,
    required this.customerId,
    required this.customerName,
    required this.outstandingAmount,
    required this.message,
    this.phoneNumber,
    this.dueDate,
  });

  factory DebtReminder.fromJson(Map<String, dynamic> json, String currency) =>
      DebtReminder(
        debtId: json['debt_id'] as String,
        customerId: json['customer_id'] as String,
        customerName: json['customer_name'] as String,
        phoneNumber: json['phone_number'] as String?,
        outstandingAmount: Money.parse(
          json['outstanding_amount'] as String,
          currency,
        ),
        dueDate: _date(json['due_date']),
        message: json['message'] as String,
      );

  final String debtId, customerId, customerName, message;
  final String? phoneNumber;
  final Money outstandingAmount;
  final DateTime? dueDate;
}

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String);

DateTime? _dateTime(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
