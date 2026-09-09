import 'package:zedbiz/core/network/api_client.dart';
import 'package:zedbiz/core/storage/token_storage.dart';
import 'package:zedbiz/features/auth/domain/user_profile.dart';

abstract interface class AuthGateway {
  Future<bool> hasSession();
  Future<void> login({required String email, required String password});
  Future<void> register({
    required String fullName,
    required String email,
    required String password,
  });
  Future<UserProfile> me();
  Future<void> logout();
  Future<void> clearSession();
}

class AuthRepository implements AuthGateway {
  AuthRepository({required this.apiClient, required this.tokenStorage});

  final ApiClient apiClient;
  final TokenStorage tokenStorage;

  @override
  Future<bool> hasSession() async => await tokenStorage.read() != null;

  @override
  Future<void> login({required String email, required String password}) async {
    final payload = await apiClient.postJson('/api/v1/auth/login', {
      'email': email,
      'password': password,
    }, authenticated: false);
    await _storeTokens(payload);
  }

  @override
  Future<void> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final payload = await apiClient.postJson('/api/v1/auth/register', {
      'full_name': fullName,
      'email': email,
      'password': password,
    }, authenticated: false);
    await _storeTokens(payload);
  }

  @override
  Future<UserProfile> me() async =>
      UserProfile.fromJson(await apiClient.getJson('/api/v1/auth/me'));

  @override
  Future<void> logout() async {
    final tokens = await tokenStorage.read();
    try {
      if (tokens != null) {
        await apiClient.postWithoutResponse('/api/v1/auth/logout', {
          'refresh_token': tokens.refreshToken,
        }, authenticated: false);
      }
    } finally {
      await tokenStorage.clear();
    }
  }

  @override
  Future<void> clearSession() => tokenStorage.clear();

  Future<void> _storeTokens(Map<String, dynamic> payload) => tokenStorage.write(
    StoredTokens(
      accessToken: payload['access_token'] as String,
      refreshToken: payload['refresh_token'] as String,
    ),
  );
}
