import 'package:zedbiz/features/commercial/domain/money.dart';

enum SubscriptionState { pending, active, gracePeriod, expired, cancelled }

enum OnboardingState { notStarted, inProgress, completed, cancelled }

enum OnboardingPaymentState { unpaid, paid, waived }

class CommercialStatus {
  const CommercialStatus({
    required this.currency,
    required this.subscriptionState,
    required this.onboardingState,
    required this.writesAllowed,
    required this.canManageCommercial,
    this.planName,
    this.planCode,
    this.planPrice,
    this.onboardingFee,
    this.onboardingPaymentState,
    this.currentPeriodEnd,
    this.graceEndsAt,
    this.daysRemaining,
  });

  factory CommercialStatus.fromJson(Map<String, dynamic> json) {
    final currency = json['currency'] as String;
    return CommercialStatus(
      planName: json['plan_name'] as String?,
      planCode: json['plan_code'] as String?,
      planPrice: json['plan_price'] == null
          ? null
          : Money.parse(json['plan_price'] as String, currency),
      currency: currency,
      subscriptionState: SubscriptionState.values.byName(
        _enumName(json['subscription_status'] as String),
      ),
      currentPeriodEnd: _date(json['current_period_end']),
      graceEndsAt: _date(json['grace_ends_at']),
      onboardingState: OnboardingState.values.byName(
        _enumName(json['onboarding_status'] as String),
      ),
      onboardingPaymentState: json['onboarding_payment_status'] == null
          ? null
          : OnboardingPaymentState.values.byName(
              _enumName(json['onboarding_payment_status'] as String),
            ),
      onboardingFee: json['onboarding_fee'] == null
          ? null
          : Money.parse(json['onboarding_fee'] as String, currency),
      writesAllowed: json['writes_allowed'] as bool,
      daysRemaining: json['days_remaining'] as int?,
      canManageCommercial: json['can_manage_commercial'] as bool,
    );
  }

  final String? planName;
  final String? planCode;
  final Money? planPrice;
  final String currency;
  final SubscriptionState subscriptionState;
  final DateTime? currentPeriodEnd;
  final DateTime? graceEndsAt;
  final OnboardingState onboardingState;
  final OnboardingPaymentState? onboardingPaymentState;
  final Money? onboardingFee;
  final bool writesAllowed;
  final int? daysRemaining;
  final bool canManageCommercial;

  static String _enumName(String value) {
    final words = value.toLowerCase().split('_');
    return words.first +
        words
            .skip(1)
            .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
            .join();
  }

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();
}
