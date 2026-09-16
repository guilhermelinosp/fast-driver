import 'dart:async';
import 'dart:convert';

import 'package:fast_driver/accept_ride_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const validDriverId = '123e4567-e89b-12d3-a456-426614174000';

class RecordingClient extends http.BaseClient {
  RecordingClient(this.responseBuilder);

  final http.Response Function(http.Request request) responseBuilder;
  http.Request? request;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final typedRequest = request as http.Request;
    this.request = typedRequest;
    final response = responseBuilder(typedRequest);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      request: typedRequest,
    );
  }
}

class FailingClient extends http.BaseClient {
  FailingClient(this.error);

  final Object error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Future<http.StreamedResponse>.error(error);
  }
}

class PendingClient extends http.BaseClient {
  PendingClient(this.response);

  final Future<http.StreamedResponse> response;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => response;
}

AcceptRideService serviceFor(RecordingClient client) => AcceptRideService(
  config: const ApiConfig(baseUrl: 'http://test.example'),
  client: client,
);

void main() {
  test('sends the real endpoint, required header, JSON content type and empty body', () async {
    final client = RecordingClient(
      (_) => http.Response('{"id":"ride-123"}', 201),
    );

    final result = await serviceFor(client)
        .acceptRide(rideId: 'ride-123', driverId: validDriverId);

    expect(result.id, 'ride-123');
    expect(client.request?.method, 'POST');
    expect(
      client.request?.url.toString(),
      'http://test.example/api/v1/drives/ride-123/accept',
    );
    expect(client.request?.headers['driver_id'], validDriverId);
    expect(client.request?.headers['content-type'], 'application/json');
    expect(client.request?.body, isEmpty);
  });

  test('parses the success response', () {
    expect(AcceptedRide.fromJson({'id': 'ride-123'}).id, 'ride-123');
  });

  test('maps the specific 409 conflict to the driver message', () async {
    final client = RecordingClient(
      (_) => http.Response(
        jsonEncode({
          'error': {
            'code': 'RIDE_ALREADY_ACCEPTED',
            'message': 'ride has already been accepted',
          },
          'requestId': 'request-123',
        }),
        409,
      ),
    );

    final call = serviceFor(client)
        .acceptRide(rideId: 'ride-123', driverId: validDriverId);

    await expectLater(
      call,
      throwsA(
        isA<AcceptRideException>()
            .having((error) => error.statusCode, 'status', 409)
            .having((error) => error.code, 'code', 'RIDE_ALREADY_ACCEPTED')
            .having((error) => error.requestId, 'requestId', 'request-123')
            .having(
              (error) => error.displayMessage,
              'display message',
              'Esta corrida já foi aceita por outro Driver.',
            ),
      ),
    );
  });

  test(
    'preserves code, message and requestId for generic HTTP errors',
    () async {
      final client = RecordingClient(
        (_) => http.Response(
          jsonEncode({
            'error': {'code': 'RIDE_NOT_FOUND', 'message': 'ride not found'},
            'requestId': 'request-404',
          }),
          404,
        ),
      );

      final call = serviceFor(client)
          .acceptRide(rideId: 'ride-123', driverId: validDriverId);

      await expectLater(
        call,
        throwsA(
          isA<AcceptRideException>()
              .having((error) => error.statusCode, 'status', 404)
              .having((error) => error.code, 'code', 'RIDE_NOT_FOUND')
              .having((error) => error.message, 'message', 'ride not found')
              .having((error) => error.requestId, 'requestId', 'request-404'),
        ),
      );
    },
  );

  test(
    'rejects missing rideId and invalid driver UUID before the request',
    () async {
      final client = RecordingClient((_) => http.Response('{}', 201));
      final service = serviceFor(client);

      await expectLater(
        service.acceptRide(rideId: '', driverId: validDriverId),
        throwsA(
          isA<AcceptRideException>().having(
            (error) => error.message,
            'message',
            'rideId é obrigatório.',
          ),
        ),
      );
      await expectLater(
        service.acceptRide(rideId: 'ride-123', driverId: 'dev'),
        throwsA(
          isA<AcceptRideException>().having(
            (error) => error.code,
            'code',
            'INVALID_DRIVER_ID',
          ),
        ),
      );
      expect(client.request, isNull);
    },
  );

  test('maps connection failures and timeouts', () async {
    final connectionService = AcceptRideService(
      config: const ApiConfig(baseUrl: 'http://test.example'),
      client: FailingClient(http.ClientException('offline')),
    );
    await expectLater(
      connectionService.acceptRide(rideId: 'ride-123', driverId: validDriverId),
      throwsA(
        isA<AcceptRideException>().having(
          (error) => error.code,
          'code',
          'CONNECTION_ERROR',
        ),
      ),
    );

    final pending = Completer<http.StreamedResponse>();
    final timeoutService = AcceptRideService(
      config: const ApiConfig(baseUrl: 'http://test.example'),
      client: PendingClient(pending.future),
      timeout: const Duration(milliseconds: 1),
    );
    await expectLater(
      timeoutService.acceptRide(rideId: 'ride-123', driverId: validDriverId),
      throwsA(
        isA<AcceptRideException>().having(
          (error) => error.code,
          'code',
          'TIMEOUT',
        ),
      ),
    );
  });
}
