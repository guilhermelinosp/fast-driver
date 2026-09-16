import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import 'accept_ride_service.dart';
import 'driver_identity_service.dart';
import 'push_notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ApiConfig.validate();
  final config = const ApiConfig();
  runApp(
    MyApp(
      service: AcceptRideService(config: config),
      offersSource: PushRideOffersService(
        receiver: const NoopPushNotificationReceiver(),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  MyApp({
    required this.service,
    RideOffersSource? offersSource,
    DriverIdProvider? driverIdProvider,
    super.key,
  }) : offersSource =
           offersSource ??
           PushRideOffersService(
             receiver: const NoopPushNotificationReceiver(),
           ),
       driverIdProvider = driverIdProvider ?? DriverIdentityService();

  final AcceptRideService service;
  final RideOffersSource offersSource;
  final DriverIdProvider driverIdProvider;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fast Driver',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: FastDriverPage(
        service: service,
        offersSource: offersSource,
        driverIdProvider: driverIdProvider,
      ),
    );
  }
}

class FastDriverPage extends StatefulWidget {
  const FastDriverPage({
    required this.service,
    required this.offersSource,
    required this.driverIdProvider,
    super.key,
  });

  final AcceptRideService service;
  final RideOffersSource offersSource;
  final DriverIdProvider driverIdProvider;

  @override
  State<FastDriverPage> createState() => _FastDriverPageState();
}

class _FastDriverPageState extends State<FastDriverPage> {
  StreamSubscription<RideOffer>? _offersSubscription;
  final Queue<RideOffer> _pendingOffers = Queue<RideOffer>();
  final Set<String> _seenRideIds = {};
  final Set<String> _hiddenRideIds = {};
  String? _driverId;
  String? _startupError;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _startPushNotifications();
  }

  Future<void> _startPushNotifications() async {
    try {
      _offersSubscription = widget.offersSource.offers.listen(_onRideOffer);
      final driverId = await widget.driverIdProvider.getOrCreate();
      if (!mounted) return;
      setState(() => _driverId = driverId);
      await widget.offersSource.start(driverId: driverId);
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _startupError = 'Não foi possível preparar o Driver: $error',
      );
    }
  }

  void _onRideOffer(RideOffer offer) {
    if (!mounted ||
        _hiddenRideIds.contains(offer.rideId) ||
        !_seenRideIds.add(offer.rideId)) {
      return;
    }
    _pendingOffers.add(offer);
    _showNextOffer();
  }

  Future<void> _showNextOffer() async {
    if (!mounted || _dialogOpen || _pendingOffers.isEmpty) return;

    final offer = _pendingOffers.removeFirst();
    if (_hiddenRideIds.contains(offer.rideId)) {
      _showNextOffer();
      return;
    }

    _dialogOpen = true;
    try {
      final result = await _showRideDialog(offer);
      if (!mounted) return;

      setState(() => _hiddenRideIds.add(offer.rideId));
      if (result == _RideDialogResult.accepted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Corrida aceita: ${offer.rideId}')),
        );
      }
    } finally {
      _dialogOpen = false;
      if (mounted) _showNextOffer();
    }
  }

  Future<_RideDialogResult?> _showRideDialog(RideOffer offer) {
    return showDialog<_RideDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var isAccepting = false;
        String? errorMessage;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isError = errorMessage != null;

            Future<void> accept() async {
              final driverId = _driverId;
              if (driverId == null || isAccepting) return;
              setDialogState(() {
                isAccepting = true;
                errorMessage = null;
              });

              try {
                await widget.service.acceptRide(
                  rideId: offer.rideId,
                  driverId: driverId,
                );
                if (!mounted || !dialogContext.mounted) return;
                Navigator.of(dialogContext).pop(_RideDialogResult.accepted);
              } on AcceptRideException catch (error) {
                if (!mounted || !dialogContext.mounted) return;
                setDialogState(() {
                  isAccepting = false;
                  errorMessage = error.displayMessage;
                });
              } on Object {
                if (!mounted || !dialogContext.mounted) return;
                setDialogState(() {
                  isAccepting = false;
                  errorMessage = 'Não foi possível aceitar a corrida.';
                });
              }
            }

            return AlertDialog(
              key: Key('ride-offer-dialog-${offer.rideId}'),
              title: const Text('Nova corrida'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ride ID: ${offer.rideId}'),
                    if (offer.riderId case final riderId?)
                      Text('Rider ID: $riderId'),
                    const SizedBox(height: 12),
                    if (offer.coordinateLabels.isEmpty)
                      const Text('Coordenadas não informadas.')
                    else
                      for (final coordinates in offer.coordinateLabels)
                        Text(coordinates),
                    if (errorMessage case final message?) ...[
                      const SizedBox(height: 16),
                      Text(
                        message,
                        key: const Key('ride-dialog-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (isError)
                  TextButton(
                    onPressed: isAccepting
                        ? null
                        : () =>
                              Navigator.of(dialogContext)
                                  .pop(_RideDialogResult.dismissed),
                    child: const Text('Fechar'),
                  ),
                TextButton(
                  onPressed: isAccepting
                      ? null
                      : () =>
                            Navigator.of(dialogContext)
                                .pop(_RideDialogResult.dismissed),
                  child: const Text('Recusar'),
                ),
                FilledButton(
                  onPressed: isAccepting ? null : accept,
                  child: Text(isAccepting ? 'Enviando...' : 'Aceitar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _offersSubscription?.cancel();
    widget.offersSource.dispose();
    widget.service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Fast Driver'),
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Aguardando novas corridas...', key: Key('empty-state')),
            if (_driverId case final driverId?) ...[
              const SizedBox(height: 8),
              Text('Driver ID: $driverId', key: const Key('driver-id')),
            ],
            if (_driverId == null) ...[
              const SizedBox(height: 8),
              const Text('Preparando identificação do Driver...'),
            ],
            if (_startupError case final error?) ...[
              const SizedBox(height: 8),
              Text(error, style: TextStyle(color: colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

enum _RideDialogResult { accepted, dismissed }
