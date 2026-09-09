import 'package:zedbiz/core/network/api_client.dart';
import 'package:zedbiz/features/businesses/domain/business_summary.dart';

abstract interface class BusinessGateway {
  Future<List<BusinessSummary>> listBusinesses();
  Future<BusinessSummary> createBusiness({
    required String name,
    String? businessType,
    String? phoneNumber,
    String? location,
  });
}

class BusinessRepository implements BusinessGateway {
  BusinessRepository(this.apiClient);

  final ApiClient apiClient;

  @override
  Future<List<BusinessSummary>> listBusinesses() async {
    final payload = await apiClient.getJsonList('/api/v1/businesses');
    return payload
        .cast<Map<String, dynamic>>()
        .map(BusinessSummary.fromJson)
        .toList(growable: false);
  }

  @override
  Future<BusinessSummary> createBusiness({
    required String name,
    String? businessType,
    String? phoneNumber,
    String? location,
  }) async {
    final payload = await apiClient.postJson('/api/v1/businesses', {
      'name': name,
      if (businessType?.isNotEmpty ?? false) 'business_type': businessType,
      if (phoneNumber?.isNotEmpty ?? false) 'phone_number': phoneNumber,
      if (location?.isNotEmpty ?? false) 'location': location,
    });
    return BusinessSummary.fromJson(payload);
  }
}
