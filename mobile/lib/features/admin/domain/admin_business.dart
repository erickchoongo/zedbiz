class AdminBusiness {
  const AdminBusiness({
    required this.id,
    required this.name,
    required this.onboardingStatus,
    required this.subscriptionStatus,
    this.onboardingPaymentStatus = 'UNPAID',
    this.ownerName,
    this.ownerEmail,
    this.paidThrough,
  });

  factory AdminBusiness.fromJson(Map<String, dynamic> json) => AdminBusiness(
    id: json['id'] as String,
    name: json['name'] as String,
    ownerName: json['owner_name'] as String?,
    ownerEmail: json['owner_email'] as String?,
    onboardingStatus: json['onboarding_status'] as String,
    onboardingPaymentStatus: json['onboarding_payment_status'] as String,
    subscriptionStatus: json['subscription_status'] as String,
    paidThrough: json['paid_through'] == null
        ? null
        : DateTime.parse(json['paid_through'] as String).toLocal(),
  );

  final String id;
  final String name;
  final String? ownerName;
  final String? ownerEmail;
  final String onboardingStatus;
  final String onboardingPaymentStatus;
  final String subscriptionStatus;
  final DateTime? paidThrough;
}
