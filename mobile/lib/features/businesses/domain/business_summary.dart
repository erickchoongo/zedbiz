enum BusinessRole { owner, manager, cashier }

class BusinessSummary {
  const BusinessSummary({
    required this.id,
    required this.name,
    required this.role,
    required this.currency,
    required this.timezone,
    this.businessType,
    this.phoneNumber,
    this.location,
  });

  factory BusinessSummary.fromJson(Map<String, dynamic> json) =>
      BusinessSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        role: BusinessRole.values.byName(
          (json['role'] as String).toLowerCase(),
        ),
        currency: json['currency'] as String,
        timezone: json['timezone'] as String,
        businessType: json['business_type'] as String?,
        phoneNumber: json['phone_number'] as String?,
        location: json['location'] as String?,
      );

  final String id;
  final String name;
  final BusinessRole role;
  final String currency;
  final String timezone;
  final String? businessType;
  final String? phoneNumber;
  final String? location;
}
