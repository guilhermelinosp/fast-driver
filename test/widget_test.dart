import 'dart:async';
import 'dart:convert';

import 'package:fast_driver/accept_ride_service.dart';
import 'package:fast_driver/driver_identity_service.dart';
import 'package:fast_driver/main.dart';
import 'package:fast_driver/push_notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const widgetDriverId = '123e4567-e89b-42d3-a456-426614174000';

class WidgetDriverIdProvider implements DriverIdProvider {
  WidgetDriverIdProvider({this.failOnGet = false, this.failWith});

  final bool failOnGet;
  final Object? failWith;

  @override
  Future<String> getOrCreate() async {
    if (failOnGet) throw failWith ?? Exception('identity failed');
    return widgetDriverId;
  }
}

class WidgetClient extends http.BaseClient {
  WidgetClient({this.postResponse});

  final http.Response? postResponse;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = postResponse ?? http.Response('{"id":"ride-123"}', 201);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(response.body)),
      response.statusCode,
      request: request,
    );
  }
}

class PushRideData {
  const PushRideData({required this.messageId, required this.data});

  final String messageId;
  final Map<String, dynamic> data;
}

Future<void> pumpApp(
  WidgetTester tester, {
  bool emitRide = false,
  List<PushRideData>? emitRides,
  http.Response? postResponse,
  DriverIdProvider? driverIdProvider,
}) async {
  final client = WidgetClient(postResponse: postResponse);
  final config = const ApiConfig(baseUrl: 'http://test.example');
  final receiver = FakePushNotificationReceiver();
  await tester.pumpWidget(
    MyApp(
      service: AcceptRideService(config: config, client: client),
      offersSource: PushRideOffersService(receiver: receiver),
      driverIdProvider: driverIdProvider ?? WidgetDriverIdProvider(),
    ),
  );
  await tester.pump();
  await tester.pump();

  if (emitRide) {
    receiver.emit(
      const PushNotification(
        eventType: 'ride.requested.v1',
        payload: {
          'id': 'ride-123',
          'pickup_latitude': -23.55,
          'pickup_longitude': -46.63,
        },
      ),
    );
  }
  for (final ride in emitRides ?? const <PushRideData>[]) {
    receiver.emit(
      PushNotification(
        eventType: 'ride.requested.v1',
        messageId: ride.messageId,
        payload: ride.data,
      ),
    );
  }
  await tester.pump();
  await tester.pump();
}

// ─── Tests ──────────────────────────────────────────────────────

void main() {
  // ─── White screen ──────────────────────────────────────────

  group('white screen', () {
    testWidgets('main screen is white with no cards', (tester) async {
      await pumpApp(tester);

      expect(find.text('Fast Driver'), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      expect(find.text('Aguardando novas corridas...'), findsOneWidget);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Colors.white,
      );
    });

    testWidgets('shows empty state text', (tester) async {
      await pumpApp(tester);

      expect(find.byKey(const Key('empty-state')), findsOneWidget);
      expect(find.text('Aguardando novas corridas...'), findsOneWidget);
    });

    testWidgets('app bar has white background', (tester) async {
      await pumpApp(tester);

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, Colors.white);
    });
  });

  // ─── Dialog popup ──────────────────────────────────────────

  group('ride offer popup', () {
    testWidgets('shows AlertDialog when ride arrives', (tester) async {
      await pumpApp(tester, emitRide: true);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Nova corrida'), findsOneWidget);
      expect(find.text('Ride ID: ride-123'), findsOneWidget);
    });

    testWidgets('shows pickup coordinates in dialog', (tester) async {
      await pumpApp(tester, emitRide: true);

      expect(find.text('Pickup: -23.55, -46.63'), findsOneWidget);
    });

    testWidgets('shows Accept and Reject buttons', (tester) async {
      await pumpApp(tester, emitRide: true);

      expect(find.text('Aceitar'), findsOneWidget);
      expect(find.text('Recusar'), findsOneWidget);
    });

    testWidgets('dialog is not dismissible by tapping outside', (tester) async {
      await pumpApp(tester, emitRide: true);

      // Try to tap outside the dialog (on the barrier)
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();

      // Dialog should still be there
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('accepts ride and closes dialog', (tester) async {
      await pumpApp(tester, emitRide: true);

      await tester.tap(find.text('Aceitar'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Corrida aceita: ride-123'), findsOneWidget);
    });

    testWidgets('rejects ride locally and closes dialog', (tester) async {
      await pumpApp(tester, emitRide: true);

      await tester.tap(find.text('Recusar'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Ride ID: ride-123'), findsNothing);
    });

    testWidgets('shows conflict error in dialog with close button', (
      tester,
    ) async {
      await pumpApp(
        tester,
        emitRide: true,
        postResponse: http.Response(
          jsonEncode({
            'error': {
              'code': 'RIDE_ALREADY_ACCEPTED',
              'message': 'already accepted',
            },
          }),
          409,
        ),
      );

      await tester.tap(find.text('Aceitar'));
      await tester.pumpAndSettle();

      expect(
        find.text('Esta corrida já foi aceita por outro Driver.'),
        findsOneWidget,
      );
      expect(find.text('Fechar'), findsOneWidget);

      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('shows loading state while accepting', (tester) async {
      final client = _LoadingClient();
      final config = const ApiConfig(baseUrl: 'http://test.example');
      final receiver = FakePushNotificationReceiver();

      await tester.pumpWidget(
        MyApp(
          service: AcceptRideService(config: config, client: client),
          offersSource: PushRideOffersService(receiver: receiver),
          driverIdProvider: WidgetDriverIdProvider(),
        ),
      );
      await tester.pump();
      await tester.pump();

      receiver.emit(
        const PushNotification(
          eventType: 'ride.requested.v1',
          payload: {'id': 'ride-loading'},
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Ride ID: ride-loading'), findsOneWidget);
      await tester.tap(find.text('Aceitar'));
      await tester.pump();

      expect(find.text('Enviando...'), findsOneWidget);
      expect(find.text('Aceitar'), findsNothing);
      expect(find.text('Recusar'), findsOneWidget);

      client.completeAccept();
      await tester.pump();
      await tester.pump();
    });

    testWidgets('shows generic error when accept fails unexpectedly', (
      tester,
    ) async {
      await pumpApp(
        tester,
        emitRide: true,
        postResponse: http.Response('oops', 500),
      );

      await tester.tap(find.text('Aceitar'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Fechar'), findsOneWidget);
    });
  });

  // ─── Driver ID display ─────────────────────────────────────

  group('driver identity', () {
    testWidgets('shows driver ID on screen', (tester) async {
      await pumpApp(tester);

      expect(find.byKey(const Key('driver-id')), findsOneWidget);
      expect(find.text('Driver ID: $widgetDriverId'), findsOneWidget);
    });

    testWidgets('shows loading when preparing identity', (tester) async {
      final provider = _SlowDriverIdProvider();
      await pumpApp(tester, driverIdProvider: provider);

      expect(
        find.text('Preparando identificação do Driver...'),
        findsOneWidget,
      );
    });

    testWidgets('shows error when identity fails', (tester) async {
      await pumpApp(
        tester,
        driverIdProvider: WidgetDriverIdProvider(
          failOnGet: true,
          failWith: Exception('storage error'),
        ),
      );

      expect(
        find.textContaining('Não foi possível preparar o Driver'),
        findsOneWidget,
      );
    });
  });

  // ─── Queue / multiple offers ───────────────────────────────

  group('offer queue', () {
    testWidgets('queues second offer and shows after first is dismissed', (
      tester,
    ) async {
      final emitRides = [
        PushRideData(
          messageId: 'message-1',
          data: {'id': 'ride-first', 'pickup_latitude': -23.0},
        ),
        PushRideData(
          messageId: 'message-2',
          data: {'id': 'ride-second', 'pickup_latitude': -24.0},
        ),
      ];

      await pumpApp(tester, emitRides: emitRides);

      // First dialog
      expect(find.text('Ride ID: ride-first'), findsOneWidget);
      expect(find.text('Ride ID: ride-second'), findsNothing);

      // Dismiss first
      await tester.tap(find.text('Recusar'));
      await tester.pumpAndSettle();

      // Second dialog should appear
      expect(find.text('Ride ID: ride-second'), findsOneWidget);
      expect(find.text('Ride ID: ride-first'), findsNothing);
    });

    testWidgets('does not show duplicate ride offers', (tester) async {
      final emitRides = [
        PushRideData(messageId: 'message-1', data: {'id': 'ride-dup'}),
        PushRideData(messageId: 'message-1', data: {'id': 'ride-dup'}),
      ];

      await pumpApp(tester, emitRides: emitRides);

      expect(find.text('Ride ID: ride-dup'), findsOneWidget);
    });

    testWidgets('accept second offer after first is accepted', (tester) async {
      final emitRides = [
        PushRideData(messageId: 'message-1', data: {'id': 'ride-a'}),
        PushRideData(messageId: 'message-2', data: {'id': 'ride-b'}),
      ];

      await pumpApp(tester, emitRides: emitRides);

      // Accept first
      expect(find.text('Ride ID: ride-a'), findsOneWidget);
      await tester.tap(find.text('Aceitar'));
      await tester.pumpAndSettle();

      // Success snackbar
      expect(find.text('Corrida aceita: ride-a'), findsOneWidget);

      // Second dialog should appear
      expect(find.text('Ride ID: ride-b'), findsOneWidget);
    });
  });

  // ─── No rides state ────────────────────────────────────────

  group('no rides', () {
    testWidgets('shows waiting text with no ride cards', (tester) async {
      await pumpApp(tester, emitRide: false);

      expect(find.text('Aguardando novas corridas...'), findsOneWidget);
      expect(find.byType(Card), findsNothing);
    });
  });
}

class _SlowDriverIdProvider implements DriverIdProvider {
  final completer = Completer<String>();

  @override
  Future<String> getOrCreate() => completer.future;
}

class _LoadingClient extends http.BaseClient {
  final _acceptCompleter = Completer<http.StreamedResponse>();

  void completeAccept() {
    _acceptCompleter.complete(
      http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('{"id":"ride-loading"}')),
        201,
      ),
    );
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return _acceptCompleter.future;
  }
}
