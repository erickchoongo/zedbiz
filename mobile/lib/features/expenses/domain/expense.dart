import 'package:zedbiz/features/commercial/domain/money.dart';

enum ExpenseCategory {
  stockPurchase,
  rent,
  utilities,
  transport,
  salariesWages,
  airtimeData,
  marketing,
  maintenance,
  equipment,
  feesCharges,
  other,
}

const _categoryApi = {
  ExpenseCategory.stockPurchase: 'STOCK_PURCHASE',
  ExpenseCategory.rent: 'RENT',
  ExpenseCategory.utilities: 'UTILITIES',
  ExpenseCategory.transport: 'TRANSPORT',
  ExpenseCategory.salariesWages: 'SALARIES_WAGES',
  ExpenseCategory.airtimeData: 'AIRTIME_DATA',
  ExpenseCategory.marketing: 'MARKETING',
  ExpenseCategory.maintenance: 'MAINTENANCE',
  ExpenseCategory.equipment: 'EQUIPMENT',
  ExpenseCategory.feesCharges: 'FEES_CHARGES',
  ExpenseCategory.other: 'OTHER',
};

String expenseCategoryApi(ExpenseCategory value) => _categoryApi[value]!;

String expenseCategoryLabel(ExpenseCategory value) => switch (value) {
  ExpenseCategory.stockPurchase => 'Stock purchase',
  ExpenseCategory.rent => 'Rent',
  ExpenseCategory.utilities => 'Utilities',
  ExpenseCategory.transport => 'Transport',
  ExpenseCategory.salariesWages => 'Salaries & wages',
  ExpenseCategory.airtimeData => 'Airtime & data',
  ExpenseCategory.marketing => 'Marketing',
  ExpenseCategory.maintenance => 'Maintenance',
  ExpenseCategory.equipment => 'Equipment',
  ExpenseCategory.feesCharges => 'Fees & charges',
  ExpenseCategory.other => 'Other',
};

ExpenseCategory expenseCategoryFromApi(String value) =>
    _categoryApi.entries.firstWhere((entry) => entry.value == value).key;

enum ExpensePaymentMethod {
  cash,
  mtnMoney,
  airtelMoney,
  zamtelMoney,
  bankTransfer,
  other,
}

String expensePaymentApi(ExpensePaymentMethod value) => switch (value) {
  ExpensePaymentMethod.cash => 'CASH',
  ExpensePaymentMethod.mtnMoney => 'MTN_MONEY',
  ExpensePaymentMethod.airtelMoney => 'AIRTEL_MONEY',
  ExpensePaymentMethod.zamtelMoney => 'ZAMTEL_MONEY',
  ExpensePaymentMethod.bankTransfer => 'BANK_TRANSFER',
  ExpensePaymentMethod.other => 'OTHER',
};

String expensePaymentLabel(ExpensePaymentMethod value) => switch (value) {
  ExpensePaymentMethod.cash => 'Cash',
  ExpensePaymentMethod.mtnMoney => 'MTN Money',
  ExpensePaymentMethod.airtelMoney => 'Airtel Money',
  ExpensePaymentMethod.zamtelMoney => 'Zamtel Money',
  ExpensePaymentMethod.bankTransfer => 'Bank transfer',
  ExpensePaymentMethod.other => 'Other',
};

ExpensePaymentMethod expensePaymentFromApi(String value) => ExpensePaymentMethod
    .values
    .firstWhere((method) => expensePaymentApi(method) == value);

enum ExpenseStatus { recorded, voided }

class ExpenseRecord {
  const ExpenseRecord({
    this.localSyncState,
    required this.id,
    required this.businessId,
    required this.category,
    required this.description,
    required this.amount,
    required this.paymentMethod,
    required this.expenseDate,
    required this.recordedByUserId,
    required this.recordedByName,
    required this.status,
    required this.createdAt,
    this.paymentReference,
    this.notes,
    this.voidedAt,
    this.voidedByName,
    this.voidReason,
  });

  factory ExpenseRecord.fromJson(Map<String, dynamic> json, String currency) =>
      ExpenseRecord(
        id: json['id'] as String,
        localSyncState: json['local_sync_state'] as String?,
        businessId: json['business_id'] as String,
        category: expenseCategoryFromApi(json['category'] as String),
        description: json['description'] as String,
        amount: Money.parse(json['amount'] as String, currency),
        paymentMethod: expensePaymentFromApi(json['payment_method'] as String),
        paymentReference: json['payment_reference'] as String?,
        expenseDate: DateTime.parse(json['expense_date'] as String),
        notes: json['notes'] as String?,
        recordedByUserId: json['recorded_by_user_id'] as String,
        recordedByName: json['recorded_by_name'] as String? ?? 'Team member',
        status: (json['status'] as String) == 'VOIDED'
            ? ExpenseStatus.voided
            : ExpenseStatus.recorded,
        voidedAt: json['voided_at'] == null
            ? null
            : DateTime.parse(json['voided_at'] as String),
        voidedByName: json['voided_by_name'] as String?,
        voidReason: json['void_reason'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String? localSyncState;
  final String id;
  final String businessId;
  final ExpenseCategory category;
  final String description;
  final Money amount;
  final ExpensePaymentMethod paymentMethod;
  final String? paymentReference;
  final DateTime expenseDate;
  final String? notes;
  final String recordedByUserId;
  final String recordedByName;
  final ExpenseStatus status;
  final DateTime? voidedAt;
  final String? voidedByName;
  final String? voidReason;
  final DateTime createdAt;
}

class ExpensePage {
  const ExpensePage({
    required this.items,
    required this.page,
    required this.total,
  });

  factory ExpensePage.fromJson(Map<String, dynamic> json, String currency) =>
      ExpensePage(
        items: (json['items'] as List<dynamic>)
            .map(
              (item) => ExpenseRecord.fromJson(
                item as Map<String, dynamic>,
                currency,
              ),
            )
            .toList(),
        page: json['page'] as int,
        total: json['total'] as int,
      );

  final List<ExpenseRecord> items;
  final int page;
  final int total;
}
