import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Real HTTP with explicit scheduling across the widget test's fake clock.
/// No response is mocked: complete sockets/body reads in runAsync, then pump
/// the UI continuations. Production ApiClient timeouts remain unchanged.
class WidgetHttp extends http.BaseClient {
  final _delegate = http.Client();
  final _pending = Queue<Future<void> Function()>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final completion = Completer<http.StreamedResponse>();
    _pending.add(() async {
      try {
        final response = await (() async => http.Response.fromStream(
          await _delegate.send(request),
        ))().timeout(const Duration(seconds: 15));
        completion.complete(
          http.StreamedResponse(
            Stream.value(response.bodyBytes),
            response.statusCode,
            headers: response.headers,
            request: request,
          ),
        );
      } catch (_) {
        completion.completeError(
          StateError(
            'Local test HTTP request failed: ${request.method} ${request.url.path}',
          ),
        );
      }
    });
    return completion.future;
  }

  Future<void> until(
    WidgetTester tester,
    bool Function() ready, {
    required String description,
  }) async {
    // Bounded UI turns, not arbitrary network sleeps. Each request is awaited
    // in real time; idle animations advance only after pending HTTP completes.
    for (var frame = 0; frame < 120; frame++) {
      while (_pending.isNotEmpty) {
        await tester.runAsync(_pending.removeFirst());
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 16));
      if (_pending.isEmpty && ready()) return;
    }
    fail('UI did not reach $description after completing local HTTP requests.');
  }

  @override
  void close() => _delegate.close();
}
