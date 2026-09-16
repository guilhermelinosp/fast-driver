import 'dart:convert';

import 'package:fast_driver/ride_offer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RideOffer.fromPushPayload', () {
    test('parses a flat push payload', () {
      final offer = RideOffer.fromPushPayload(
        eventType: 'ride.requested.v1',
        messageId: 'message-1',
        payload: const {
          'id': 'ride-1',
          'rider_id': 'rider-1',
          'pickup_latitude': -23.55,
          'pickup_longitude': -46.63,
          'destination_latitude': -23.56,
          'destination_longitude': -46.65,
        },
      );

      expect(offer.rideId, 'ride-1');
      expect(offer.riderId, 'rider-1');
      expect(offer.eventId, 'message-1');
      expect(offer.pickupLatitude, -23.55);
      expect(offer.pickupLongitude, -46.63);
      expect(offer.destinationLatitude, -23.56);
      expect(offer.destinationLongitude, -46.65);
    });

    test('parses a JSON string and nested ride envelope', () {
      final offer = RideOffer.fromPushPayload(
        eventType: 'ride.requested.v1',
        messageId: 'message-2',
        payload: jsonEncode({
          'ride': {
            'rideId': 'ride-2',
            'riderId': 'rider-2',
            'pickup': {'lat': -23.55, 'lng': -46.63},
            'destination': {'latitude': -23.56, 'longitude': -46.65},
          },
        }),
      );

      expect(offer.rideId, 'ride-2');
      expect(offer.riderId, 'rider-2');
      expect(offer.pickupLatitude, -23.55);
      expect(offer.pickupLongitude, -46.63);
      expect(offer.destinationLatitude, -23.56);
      expect(offer.destinationLongitude, -46.65);
    });

    test('uses the payload event_id when messageId is omitted', () {
      final offer = RideOffer.fromPushPayload(
        eventType: 'ride.requested.v1',
        payload: const {'event_id': 'event-3', 'id': 'ride-3'},
      );

      expect(offer.eventId, 'event-3');
    });

    test('uses messageId as ride id when the payload has no ride id', () {
      final offer = RideOffer.fromPushPayload(
        eventType: 'ride.requested.v1',
        messageId: 'message-4',
        payload: const {'rider_id': 'rider-4'},
      );

      expect(offer.rideId, 'message-4');
    });

    test('rejects an unrelated push event', () {
      expect(
        () => RideOffer.fromPushPayload(
          eventType: 'driver.status.changed.v1',
          payload: const {'id': 'ride-5'},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-object and malformed payloads', () {
      expect(
        () => RideOffer.fromPushPayload(
          eventType: 'ride.requested.v1',
          payload: const <Object>['ride-6'],
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => RideOffer.fromPushPayload(
          eventType: 'ride.requested.v1',
          payload: 'not-json',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => RideOffer.fromPushPayload(
          eventType: 'ride.requested.v1',
          payload: const {'rider_id': 'rider-6'},
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('RideOffer.coordinateLabels', () {
    test('includes complete pickup and destination coordinates', () {
      const offer = RideOffer(
        rideId: 'ride-1',
        pickupLatitude: -23.55,
        pickupLongitude: -46.63,
        destinationLatitude: -23.56,
        destinationLongitude: -46.65,
      );

      expect(offer.coordinateLabels, [
        'Pickup: -23.55, -46.63',
        'Destino: -23.56, -46.65',
      ]);
    });

    test('omits incomplete coordinate pairs', () {
      const offer = RideOffer(rideId: 'ride-1', pickupLatitude: -23.55);

      expect(offer.coordinateLabels, isEmpty);
    });
  });
}
