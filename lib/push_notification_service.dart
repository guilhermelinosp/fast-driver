import 'dart:async';

import 'ride_offer.dart';

export 'ride_offer.dart' show RideOffer;

/// Provider-neutral notification delivered by an APNs/FCM gateway adapter.
///
/// The push plugin is deliberately not a dependency of this package. Its
/// callback only needs to be converted to this value before entering the app.
class PushNotification {
  const PushNotification({
    required this.eventType,
    required this.payload,
    this.messageId,
  });

  final String eventType;
  final Object payload;
  final String? messageId;

  /// Converts a provider callback into the app's small, stable contract.
  ///
  /// Both FCM data messages and APNs custom dictionaries can be normalized by
  /// the future plugin adapter as long as they expose `type` (or `event`) and
  /// `data`. `data` may be a JSON object or a JSON string.
  factory PushNotification.fromProviderPayload(
    Map<String, dynamic> providerPayload, {
    String? messageId,
  }) {
    final eventType =
        _stringValue(providerPayload['type']) ??
        _stringValue(providerPayload['event']) ??
        _stringValue(providerPayload['event_type']);
    final payload = providerPayload['data'] ?? providerPayload['payload'];

    if (eventType == null || payload == null) {
      throw const FormatException('Push payload must contain type and data.');
    }

    return PushNotification(
      eventType: eventType,
      payload: payload,
      messageId:
          messageId ??
          _stringValue(providerPayload['message_id']) ??
          _stringValue(providerPayload['event_id']),
    );
  }

  static String? _stringValue(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}

/// Boundary implemented by the APNs/FCM plugin integration.
abstract interface class PushNotificationReceiver {
  Stream<PushNotification> get notifications;

  Future<void> start({required String driverId});

  Future<void> dispose();
}

/// Domain-facing source consumed by the UI, independent of the push vendor.
abstract interface class RideOffersSource {
  Stream<RideOffer> get offers;

  Future<void> start({required String driverId});

  Future<void> dispose();
}

/// Transforms a normalized push notification into a domain offer.
class RideOfferPayloadAdapter {
  const RideOfferPayloadAdapter();

  RideOffer? tryParse(PushNotification notification) {
    try {
      return RideOffer.fromPushPayload(
        eventType: notification.eventType,
        messageId: notification.messageId,
        payload: notification.payload,
      );
    } on Object {
      // A malformed provider message must not stop future notifications.
      return null;
    }
  }
}

/// Push-backed offer source used by the main flow.
class PushRideOffersService implements RideOffersSource {
  PushRideOffersService({
    required this.receiver,
    this.payloadAdapter = const RideOfferPayloadAdapter(),
  });

  final PushNotificationReceiver receiver;
  final RideOfferPayloadAdapter payloadAdapter;

  bool _disposed = false;

  @override
  Stream<RideOffer> get offers async* {
    if (_disposed) return;

    await for (final notification in receiver.notifications) {
      if (_disposed) return;
      final offer = payloadAdapter.tryParse(notification);
      if (offer != null) yield offer;
    }
  }

  @override
  Future<void> start({required String driverId}) {
    if (_disposed) return Future<void>.value();
    return receiver.start(driverId: driverId);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await receiver.dispose();
  }
}

/// Safe default until the platform push plugin is integrated.
class NoopPushNotificationReceiver implements PushNotificationReceiver {
  const NoopPushNotificationReceiver();

  @override
  Stream<PushNotification> get notifications => const Stream.empty();

  @override
  Future<void> start({required String driverId}) async {}

  @override
  Future<void> dispose() async {}
}

/// In-memory receiver for unit/widget tests and local development.
class FakePushNotificationReceiver implements PushNotificationReceiver {
  FakePushNotificationReceiver() : _controller = StreamController.broadcast();

  final StreamController<PushNotification> _controller;
  String? startedDriverId;
  bool disposed = false;

  @override
  Stream<PushNotification> get notifications => _controller.stream;

  @override
  Future<void> start({required String driverId}) async {
    if (disposed) return;
    startedDriverId = driverId;
  }

  void emit(PushNotification notification) {
    if (!disposed) _controller.add(notification);
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await _controller.close();
  }
}
