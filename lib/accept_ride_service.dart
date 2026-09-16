import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiConfig {
  const ApiConfig({this.baseUrl = compileTimeBaseUrl});

  static const compileTimeBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// All env vars are REQUIRED. The app will not start without them.
  static void validate() {
    if (compileTimeBaseUrl.isEmpty) {
      throw StateError(
        'API_BASE_URL is required. Pass it with --dart-define-from-file=.env '
        'or --dart-define=API_BASE_URL=...',
      );
    }
  }

  final String baseUrl;

  Uri acceptRideUri(String rideId) {
    final normalizedBaseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse(
      '$normalizedBaseUrl/api/v1/drives/${Uri.encodeComponent(rideId)}/accept',
    );
  }
}

class AcceptedRide {
  const AcceptedRide({required this.id});

  final String id;

  factory AcceptedRide.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException(
        'success response must contain a non-empty id',
      );
    }
    return AcceptedRide(id: id);
  }
}

class AcceptRideException implements Exception {
  const AcceptRideException({
    required this.message,
    this.statusCode,
    this.code,
    this.requestId,
  });

  final String message;
  final int? statusCode;
  final String? code;
  final String? requestId;

  bool get isAlreadyAccepted =>
      statusCode == 409 && code == 'RIDE_ALREADY_ACCEPTED';

  String get displayMessage {
    if (isAlreadyAccepted) {
      return 'Esta corrida já foi aceita por outro Driver.';
    }

    final details = <String>[
      if (code case final value? when value.isNotEmpty) 'code: $value',
      if (message.isNotEmpty) message,
      if (requestId case final value? when value.isNotEmpty)
        'requestId: $value',
    ];
    return details.isEmpty
        ? 'Não foi possível aceitar a corrida.'
        : details.join('\n');
  }

  @override
  String toString() =>
      'AcceptRideException(statusCode: $statusCode, code: $code, '
      'message: $message, requestId: $requestId)';
}

class AcceptRideService {
  AcceptRideService({
    required this.config,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final ApiConfig config;
  final http.Client _client;
  final Duration timeout;

  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  Future<AcceptedRide> acceptRide({
    required String rideId,
    required String driverId,
  }) async {
    final normalizedRideId = rideId.trim();
    final normalizedDriverId = driverId.trim();
    _validate(normalizedRideId, normalizedDriverId);

    late http.Response response;
    try {
      response = await _client
          .post(
            config.acceptRideUri(normalizedRideId),
            headers: {
              'Content-Type': 'application/json',
              'driver_id': normalizedDriverId,
            },
            body: '',
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AcceptRideException(
        code: 'TIMEOUT',
        message: 'Tempo esgotado ao conectar ao backend.',
      );
    } on http.ClientException {
      throw const AcceptRideException(
        code: 'CONNECTION_ERROR',
        message: 'Não foi possível conectar ao backend.',
      );
    }

    return _parseResponse(response);
  }

  void dispose() => _client.close();

  void _validate(String rideId, String driverId) {
    if (rideId.isEmpty) {
      throw const AcceptRideException(message: 'rideId é obrigatório.');
    }
    if (driverId.isEmpty) {
      throw const AcceptRideException(message: 'driverId é obrigatório.');
    }
    if (!_uuidPattern.hasMatch(driverId)) {
      throw const AcceptRideException(
        code: 'INVALID_DRIVER_ID',
        message: 'driverId deve ser um UUID válido.',
      );
    }
  }

  AcceptedRide _parseResponse(http.Response response) {
    if (response.statusCode == 201) {
      try {
        final body = jsonDecode(response.body);
        if (body is! Map<String, dynamic>) {
          throw const FormatException('success response must be an object');
        }
        return AcceptedRide.fromJson(body);
      } on FormatException catch (error) {
        throw AcceptRideException(
          statusCode: response.statusCode,
          code: 'INVALID_RESPONSE',
          message: error.message,
        );
      } on Object {
        throw const AcceptRideException(
          statusCode: 201,
          code: 'INVALID_RESPONSE',
          message: 'Resposta de sucesso inválida.',
        );
      }
    }

    final body = _decodeObject(response.body);
    final error = body?['error'];
    final errorMap = error is Map<String, dynamic> ? error : null;
    throw AcceptRideException(
      statusCode: response.statusCode,
      code: errorMap?['code'] as String? ?? 'HTTP_${response.statusCode}',
      message:
          errorMap?['message'] as String? ??
          'Backend respondeu HTTP ${response.statusCode}.',
      requestId: body?['requestId'] as String?,
    );
  }

  Map<String, dynamic>? _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
