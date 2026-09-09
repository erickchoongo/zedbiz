import 'dart:async';

import 'package:zedbiz/core/network/api_exception.dart';
import 'package:zedbiz/features/auth/data/auth_repository.dart';
import 'package:zedbiz/features/auth/domain/user_profile.dart';
import 'package:zedbiz/features/businesses/data/business_repository.dart';
import 'package:zedbiz/features/businesses/domain/business_summary.dart';
import 'package:zedbiz/features/commercial/data/commercial_repository.dart';
import 'package:zedbiz/features/commercial/domain/commercial_status.dart';
import 'package:zedbiz/features/commercial/domain/money.dart';
import 'package:zedbiz/features/admin/data/admin_repository.dart';
import 'package:zedbiz/features/admin/domain/admin_business.dart';

const testUser = UserProfile(
  id: 'user-1',
  email: 'owner@example.com',
  fullName: 'Test Owner',
  phoneNumber: null,
);

const testBusinessA = BusinessSummary(
  id: 'business-a',
  name: 'Brown Tech',
  role: BusinessRole.owner,
  currency: 'ZMW',
  timezone: 'Africa/Lusaka',
);

const testBusinessB = BusinessSummary(
  id: 'business-b',
  name: 'Green Market',
  role: BusinessRole.manager,
  currency: 'ZMW',
  timezone: 'Africa/Lusaka',
);

class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({this.sessionAvailable = false, this.user = testUser});

  bool sessionAvailable;
  final UserProfile user;
  bool loggedOut = false;
  bool cleared = false;
  int loginCalls = 0;
  int registerCalls = 0;
  Object? loginError;
  Completer<void>? loginGate;

  @override
  Future<void> clearSession() async {
    cleared = true;
    sessionAvailable = false;
  }

  @override
  Future<bool> hasSession() async => sessionAvailable;

  @override
  Future<void> login({required String email, required String password}) async {
    loginCalls++;
    if (loginGate != null) await loginGate!.future;
    if (loginError != null) throw loginError!;
    sessionAvailable = true;
  }

  @override
  Future<void> logout() async {
    loggedOut = true;
    sessionAvailable = false;
  }

  @override
  Future<UserProfile> me() async => user;

  @override
  Future<void> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    registerCalls++;
    sessionAvailable = true;
  }
}

class FakeBusinessGateway implements BusinessGateway {
  FakeBusinessGateway({List<BusinessSummary> businesses = const []})
    : items = [...businesses];

  final List<BusinessSummary> items;
  Object? createError;

  @override
  Future<BusinessSummary> createBusiness({
    required String name,
    String? businessType,
    String? phoneNumber,
    String? location,
  }) async {
    if (createError != null) throw createError!;
    final business = BusinessSummary(
      id: 'created-business',
      name: name,
      role: BusinessRole.owner,
      currency: 'ZMW',
      timezone: 'Africa/Lusaka',
      businessType: businessType,
      phoneNumber: phoneNumber,
      location: location,
    );
    items.add(business);
    return business;
  }

  @override
  Future<List<BusinessSummary>> listBusinesses() async =>
      List.unmodifiable(items);
}

ApiException testApiError([String message = 'Request failed']) =>
    ApiException(message, statusCode: 400);

final activeCommercialStatus = CommercialStatus(
  planName: 'Founder',
  planCode: 'FOUNDER',
  planPrice: Money.parse('79.00', 'ZMW'),
  currency: 'ZMW',
  subscriptionState: SubscriptionState.active,
  currentPeriodEnd: DateTime.utc(2026, 9, 30),
  graceEndsAt: DateTime.utc(2026, 10, 7),
  onboardingState: OnboardingState.completed,
  onboardingPaymentState: OnboardingPaymentState.paid,
  onboardingFee: Money.parse('200.00', 'ZMW'),
  writesAllowed: true,
  canManageCommercial: true,
);

class FakeCommercialGateway implements CommercialGateway {
  FakeCommercialGateway({CommercialStatus? status})
    : status = status ?? activeCommercialStatus;
  CommercialStatus status;
  Object? error;
  int calls = 0;

  @override
  Future<CommercialStatus> getStatus(String businessId) async {
    calls++;
    if (error != null) throw error!;
    return status;
  }
}

class FakeAdminGateway implements AdminGateway {
  List<AdminBusiness> businesses = const [];

  @override
  Future<void> activate(
    String businessId, {
    required String method,
    required String reference,
  }) async {}
  @override
  Future<Map<String, dynamic>> commercialDetail(String businessId) async => {};
  @override
  Future<List<AdminBusiness>> listBusinesses({
    String? search,
    String? onboardingStatus,
    String? subscriptionStatus,
  }) async => businesses;
  @override
  Future<void> renew(
    String businessId, {
    required String method,
    required String reference,
  }) async {}
  @override
  Future<void> updateOnboarding(
    String businessId,
    Map<String, dynamic> update,
  ) async {}
}
