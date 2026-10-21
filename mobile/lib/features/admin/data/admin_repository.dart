import 'package:zedbiz/core/network/api_client.dart';
import 'package:zedbiz/features/admin/domain/admin_business.dart';

abstract interface class AdminGateway {
  Future<List<AdminBusiness>> listBusinesses({
    String? search,
    String? onboardingStatus,
    String? subscriptionStatus,
  });
  // Platform access controls (independent of subscriptions).
  Future<Map<String, dynamic>> businessAccess(String businessId);
  Future<Map<String, dynamic>> changeBusinessAccess(String businessId, {required bool suspend, String? reason});
  Future<List<Map<String, dynamic>>> listAccessUsers({String? email});
  Future<Map<String, dynamic>> changeUserAccess(String userId, {required bool suspend, String? reason});
  Future<List<Map<String, dynamic>>> listAccessMemberships(String businessId);
  Future<Map<String, dynamic>> changeMembershipAccess(String businessId, String userId, {required bool suspend, String? reason});
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
    final businesses = <AdminBusiness>[];
    var page = 1;
    int? expectedTotal;
    final ids = <String>{};
    while (true) {
      parameters['page'] = '$page';
      parameters['page_size'] = '100';
      final query = Uri(queryParameters: parameters).query;
      final payload = await apiClient.getJson(
        '/api/v1/admin/businesses?$query',
      );
      final total = payload['total'];
      if (total is! int ||
          total < 0 ||
          payload['page'] != page ||
          payload['page_size'] != 100 ||
          (expectedTotal != null && total != expectedTotal)) {
        throw const FormatException(
          'Invalid or changing admin pagination; retry the listing.',
        );
      }
      expectedTotal = total;
      final items = (payload['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(AdminBusiness.fromJson)
          .toList();
      if (items.length > 100 ||
          items.any((item) => !ids.add(item.id)) ||
          businesses.length + items.length > total) {
        throw const FormatException('Invalid or repeated admin page.');
      }
      businesses.addAll(items);
      if (businesses.length >= total) break;
      if (items.isEmpty) throw StateError('Incomplete business listing');
      page++;
    }
    return businesses;
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
  static const _access = '/api/v1/admin/access';

  @override
  Future<Map<String, dynamic>> businessAccess(String businessId) =>
      apiClient.getJson('$_access/businesses/$businessId/access');

  @override
  Future<Map<String, dynamic>> changeBusinessAccess(String businessId, {required bool suspend, String? reason}) =>
      apiClient.postJson('$_access/businesses/$businessId/${suspend ? 'suspend' : 'reactivate'}',
          suspend ? {'reason': reason} : <String, dynamic>{});

  @override
  Future<List<Map<String, dynamic>>> listAccessUsers({String? email}) async {
    final query = email == null || email.trim().isEmpty ? '' : '?${Uri(queryParameters: {'email': email.trim()}).query}';
    final rows = await apiClient.getJsonList('$_access/users$query');
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> changeUserAccess(String userId, {required bool suspend, String? reason}) =>
      apiClient.postJson('$_access/users/$userId/${suspend ? 'suspend' : 'reactivate'}',
          suspend ? {'reason': reason} : <String, dynamic>{});

  @override
  Future<List<Map<String, dynamic>>> listAccessMemberships(String businessId) async {
    final rows = await apiClient.getJsonList('$_access/businesses/$businessId/memberships');
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> changeMembershipAccess(String businessId, String userId, {required bool suspend, String? reason}) =>
      apiClient.postJson('$_access/businesses/$businessId/memberships/$userId/${suspend ? 'suspend' : 'reactivate'}',
          suspend ? {'reason': reason} : <String, dynamic>{});

}
