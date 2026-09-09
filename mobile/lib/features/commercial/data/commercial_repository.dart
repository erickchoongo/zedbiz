import 'package:zedbiz/core/network/api_client.dart';
import 'package:zedbiz/features/commercial/domain/commercial_status.dart';

abstract interface class CommercialGateway {
  Future<CommercialStatus> getStatus(String businessId);
}

class CommercialRepository implements CommercialGateway {
  CommercialRepository(this.apiClient);
  final ApiClient apiClient;

  @override
  Future<CommercialStatus> getStatus(String businessId) async =>
      CommercialStatus.fromJson(
        await apiClient.getJson(
          '/api/v1/businesses/$businessId/commercial-status',
        ),
      );
}
