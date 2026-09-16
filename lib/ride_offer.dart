import 'dart:convert';

class RideOffer {
  const RideOffer({
    required this.rideId,
    this.riderId,
    this.eventId,
    this.pickupLatitude,
    this.pickupLongitude,
    this.destinationLatitude,
    this.destinationLongitude,
  });

  final String rideId;
  final String? riderId;
  final String? eventId;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;

  factory RideOffer.fromPushPayload({
    required String eventType,
    required Object payload,
    String? messageId,
  }) {
    if (eventType != 'ride.requested.v1') {
      throw const FormatException('Unsupported push event.');
    }

    final decoded = _decodePayload(payload);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ride.requested data must be an object.');
    }

    final ride = decoded['ride'];
    final ridePayload = ride is Map
        ? ride.map((key, value) => MapEntry(key.toString(), value))
        : decoded;
    final effectiveMessageId = messageId ?? _stringValue(decoded['event_id']);

    final rideId =
        _stringValue(ridePayload['id']) ??
        _stringValue(ridePayload['rideId']) ??
        (effectiveMessageId?.isNotEmpty == true ? effectiveMessageId : null);
    if (rideId == null) {
      throw const FormatException('ride.requested must contain id or rideId.');
    }

    return RideOffer(
      rideId: rideId,
      riderId:
          _stringValue(ridePayload['rider_id']) ??
          _stringValue(ridePayload['riderId']),
      eventId: effectiveMessageId,
      pickupLatitude:
          _coordinate(ridePayload, 'pickup', 'latitude') ??
          _numberValue(ridePayload['pickup_latitude']) ??
          _numberValue(ridePayload['pickupLatitude']),
      pickupLongitude:
          _coordinate(ridePayload, 'pickup', 'longitude') ??
          _numberValue(ridePayload['pickup_longitude']) ??
          _numberValue(ridePayload['pickupLongitude']),
      destinationLatitude:
          _coordinate(ridePayload, 'destination', 'latitude') ??
          _numberValue(ridePayload['destination_latitude']) ??
          _numberValue(ridePayload['destinationLatitude']),
      destinationLongitude:
          _coordinate(ridePayload, 'destination', 'longitude') ??
          _numberValue(ridePayload['destination_longitude']) ??
          _numberValue(ridePayload['destinationLongitude']),
    );
  }

  List<String> get coordinateLabels => [
    if (pickupLatitude != null && pickupLongitude != null)
      'Pickup: $pickupLatitude, $pickupLongitude',
    if (destinationLatitude != null && destinationLongitude != null)
      'Destino: $destinationLatitude, $destinationLongitude',
  ];

  static String? _stringValue(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  static double? _numberValue(Object? value) =>
      value is num ? value.toDouble() : null;

  static Object? _decodePayload(Object payload) {
    if (payload is String) return jsonDecode(payload);
    if (payload is Map<String, dynamic>) return payload;
    if (payload is Map) {
      return payload.map((key, value) => MapEntry(key.toString(), value));
    }
    return payload;
  }

  static double? _coordinate(
    Map<String, dynamic> json,
    String group,
    String coordinate,
  ) {
    final nested = json[group];
    if (nested is! Map) return null;
    return _numberValue(nested[coordinate]) ??
        _numberValue(nested[coordinate == 'latitude' ? 'lat' : 'lng']);
  }
}
