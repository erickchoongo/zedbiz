import 'package:zedbiz/features/commercial/domain/money.dart';
import 'package:zedbiz/features/debts/domain/debt.dart';

class CustomerSummary {
  const CustomerSummary({
    required this.id,
    required this.businessId,
    required this.name,
    required this.isActive,
    required this.totalOutstanding,
    required this.totalOverdue,
    required this.openDebtCount,
    this.phoneNumber,
    this.email,
  });

  factory CustomerSummary.fromJson(
    Map<String, dynamic> json,
    String currency,
  ) => CustomerSummary(
    id: json['id'] as String,
    businessId: json['business_id'] as String,
    name: json['name'] as String,
    phoneNumber: json['phone_number'] as String?,
    email: json['email'] as String?,
    isActive: json['is_active'] as bool,
    totalOutstanding: Money.parse(
      json['total_outstanding'] as String? ?? '0.00',
      currency,
    ),
    totalOverdue: Money.parse(
      json['total_overdue'] as String? ?? '0.00',
      currency,
    ),
    openDebtCount: json['open_debt_count'] as int? ?? 0,
  );

  final String id, businessId, name;
  final String? phoneNumber, email;
  final bool isActive;
  final Money totalOutstanding, totalOverdue;
  final int openDebtCount;
}

class CustomerDetail extends CustomerSummary {
  const CustomerDetail({
    required super.id,
    required super.businessId,
    required super.name,
    required super.isActive,
    required super.totalOutstanding,
    required super.totalOverdue,
    required super.openDebtCount,
    required this.recentDebts,
    super.phoneNumber,
    super.email,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory CustomerDetail.fromJson(Map<String, dynamic> json, String currency) {
    final summary = CustomerSummary.fromJson(json, currency);
    return CustomerDetail(
      id: summary.id,
      businessId: summary.businessId,
      name: summary.name,
      phoneNumber: summary.phoneNumber,
      email: summary.email,
      isActive: summary.isActive,
      totalOutstanding: summary.totalOutstanding,
      totalOverdue: summary.totalOverdue,
      openDebtCount: summary.openDebtCount,
      notes: json['notes'] as String?,
      createdAt: _dateTime(json['created_at']),
      updatedAt: _dateTime(json['updated_at']),
      recentDebts: (json['recent_debts'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                DebtSummary.fromJson(item as Map<String, dynamic>, currency),
          )
          .toList(),
    );
  }

  final String? notes;
  final DateTime? createdAt, updatedAt;
  final List<DebtSummary> recentDebts;
}

class CustomerPage {
  const CustomerPage(this.items, this.page, this.pageSize, this.total);

  factory CustomerPage.fromJson(Map<String, dynamic> json, String currency) =>
      CustomerPage(
        (json['items'] as List<dynamic>)
            .map(
              (item) => CustomerSummary.fromJson(
                item as Map<String, dynamic>,
                currency,
              ),
            )
            .toList(),
        json['page'] as int,
        json['page_size'] as int,
        json['total'] as int,
      );

  final List<CustomerSummary> items;
  final int page, pageSize, total;
}

/// Client-side feedback only; the API performs authoritative normalization.
String? customerPhoneError(String? value) {
  final input = value?.trim() ?? '';
  if (input.isEmpty) return null;
  final compact = input.replaceAll(RegExp(r'[\s\-()]'), '');
  final valid =
      RegExp(r'^0\d{9}$').hasMatch(compact) ||
      RegExp(r'^260\d{9}$').hasMatch(compact) ||
      RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(compact);
  return valid
      ? null
      : 'Use 097xxxxxxx, 26097xxxxxxx, or a valid +country number.';
}

DateTime? _dateTime(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
