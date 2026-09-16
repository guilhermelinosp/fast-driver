import 'dart:async';

import 'package:fast_driver/push_notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PushNotification.fromProviderPayload', () {
    test('normalizes an FCM/APNs-shaped payload', () {
      final notification = PushNotification.fromProviderPayload({
        'type': 'ride.requested.v1',
        'data': '{"id":"ride-1"}',
        'message_id': 'message-1',
      });

      expect(notification.eventType, 'ride.requested.v1');
      expect(notification.payload, '{"id":"ride-1"}');
      expect(notification.messageId, 'message-1');
    });

    test('accepts event and payload aliases', () {
      final notification = PushNotification.fromProviderPayload({
        'event': 'ride.requested.v1',
        'payload': {'id': 'ride-2'},
      });

      expect(notification.eventType, 'ride.requested.v1');
      expect(notification.payload, {'id': 'ride-2'});
    });

    test('uses webhook event_id as the provider message id', () {
      final notification = PushNotification.fromProviderPayload({
        'event': 'ride.requested.v1',
        'event_id': 'event-3',
        'data': {'id': 'ride-3'},
      });

      expect(notification.messageId, 'event-3');
    });

    test('rejects a provider payload without type or data', () {
      expect(
        () => PushNotification.fromProviderPayload({
          'data': {'id': 'ride-1'},
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () =>
            PushNotification.fromProviderPayload({'type': 'ride.requested.v1'}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('RideOfferPayloadAdapter', () {
    const adapter = RideOfferPayloadAdapter();

    test('transforms a valid ride.requested.v1 object', () {
      final offer = adapter.tryParse(
        const PushNotification(
          eventType: 'ride.requested.v1',
          messageId: 'message-1',
          payload: {
            'id': 'ride-1',
            'rider_id': 'rider-1',
            'pickup': {'lat': -23.55, 'lng': -46.63},
          },
        ),
      );

      expect(offer, isNotNull);
      expect(offer!.rideId, 'ride-1');
      expect(offer.eventId, 'message-1');
      expect(offer.pickupLatitude, -23.55);
      expect(offer.pickupLongitude, -46.63);
    });

    test('transforms valid JSON string data', () {
      final offer = adapter.tryParse(
        const PushNotification(
          eventType: 'ride.requested.v1',
          payload: '{"rideId":"ride-json"}',
        ),
      );

      expect(offer?.rideId, 'ride-json');
    });

    test('transforms the backend webhook envelope', () {
      final notification = PushNotification.fromProviderPayload({
        'event': 'ride.requested.v1',
        'event_id': 'event-webhook',
        'data': {
          'event': 'ride.requested.v1',
          'event_id': 'event-webhook',
          'ride': {
            'rideId': 'ride-webhook',
            'riderId': 'rider-webhook',
            'pickupLatitude': -23.55,
            'pickupLongitude': -46.63,
          },
        },
      });

      final offer = const RideOfferPayloadAdapter().tryParse(notification);
      expect(offer?.rideId, 'ride-webhook');
      expect(offer?.riderId, 'rider-webhook');
      expect(offer?.eventId, 'event-webhook');
      expect(offer?.pickupLatitude, -23.55);
      expect(offer?.pickupLongitude, -46.63);
    });

    test('returns null for malformed JSON and missing ride id', () {
      expect(
        adapter.tryParse(
          const PushNotification(
            eventType: 'ride.requested.v1',
            payload: 'not-json',
          ),
        ),
        isNull,
      );
      expect(
        adapter.tryParse(
          const PushNotification(
            eventType: 'ride.requested.v1',
            payload: {'pickup_latitude': 1},
          ),
        ),
        isNull,
      );
    });

    test('returns null for an unrelated event', () {
      expect(
        adapter.tryParse(
          const PushNotification(
            eventType: 'driver.status.changed.v1',
            payload: {'id': 'not-a-ride'},
          ),
        ),
        isNull,
      );
    });
  });

  group('PushRideOffersService', () {
    test('forwards valid offers and ignores malformed notifications', () async {
      final receiver = FakePushNotificationReceiver();
      final service = PushRideOffersService(receiver: receiver);
      final offersFuture = service.offers.take(1).toList();

      await service.start(driverId: 'driver-1');
      receiver.emit(
        const PushNotification(
          eventType: 'ride.requested.v1',
          payload: 'bad-json',
        ),
      );
      receiver.emit(
        const PushNotification(
          eventType: 'ride.requested.v1',
          payload: {'id': 'ride-1'},
        ),
      );

      final offers = await offersFuture;
      expect(offers.single.rideId, 'ride-1');
      expect(receiver.startedDriverId, 'driver-1');
      await service.dispose();
    });

    test('does not emit after disposal', () async {
      final receiver = FakePushNotificationReceiver();
      final service = PushRideOffersService(receiver: receiver);
      final emitted = <RideOffer>[];
      final subscription = service.offers.listen(emitted.add);

      await service.dispose();
      receiver.emit(
        const PushNotification(
          eventType: 'ride.requested.v1',
          payload: {'id': 'ride-ignored'},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isEmpty);
      await subscription.cancel();
    });

    test('fake receiver closes its stream on disposal', () async {
      final receiver = FakePushNotificationReceiver();
      final done = Completer<void>();
      receiver.notifications.listen(null, onDone: done.complete);

      await receiver.dispose();
      await done.future;
      expect(receiver.disposed, isTrue);
    });
  });
}
