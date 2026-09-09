class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class SessionExpiredException extends ApiException {
  const SessionExpiredException()
    : super('Your session has expired. Please sign in again.', statusCode: 401);
}
