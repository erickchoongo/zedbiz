import 'package:zedbiz/core/network/api_client.dart';
import 'package:zedbiz/features/admin/domain/admin_business.dart';

abstract interface class AdminGateway {
  Future<List<AdminBusiness>> listBusinesses({
    String? search,
    String? onboardingStatus,
    String? subscriptionStatus,
  });
  Future<Map<String, dynamic>> commercialDetail(String businessId);
  Future<void> updateOnboarding(String businessId, Map<String, dynamic> update);
  Future<void> activate(
    String businessId, {
    required String method,
    required String reference,
  });
  Future<void> renew(
    String businessId, {
    required String method,
    required String reference,
  });
}

class AdminRepository implements AdminGateway {
  AdminRepository(this.apiClient);
  final ApiClient apiClient;

  @override
  Future<List<AdminBusiness>> listBusinesses({
    String? search,
    String? onboardingStatus,
    String? subscriptionStatus,
  }) async {
    final parameters = <String, String>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'onboarding_status': ?onboardingStatus,
      'subscription_status': ?subscriptionStatus,
    };
    final query = parameters.isEmpty
        ? ''
        : '?${Uri(queryParameters: parameters).query}';
    final payload = await apiClient.getJson('/api/v1/admin/businesses$query');
    return (payload['items'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(AdminBusiness.fromJson)
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> commercialDetail(String businessId) =>
      apiClient.getJson('/api/v1/admin/businesses/$businessId/commercial');

  @override
  Future<void> updateOnboarding(
    String businessId,
    Map<String, dynamic> update,
  ) async {
    await apiClient.patchJson(
      '/api/v1/admin/businesses/$businessId/onboarding',
      update,
    );
  }

  @override
  Future<void> activate(
    String businessId, {
    required String method,
    required String reference,
  }) async {
    await apiClient.postJson(
      '/api/v1/admin/businesses/$businessId/subscription/activate',
      {'payment_method': method, 'payment_reference': reference},
    );
  }

  @override
  Future<void> renew(
    String businessId, {
    required String method,
    required String reference,
  }) async {
    await apiClient.postJson(
      '/api/v1/admin/businesses/$businessId/subscription/renew',
      {'payment_method': method, 'payment_reference': reference},
    );
  }
}
