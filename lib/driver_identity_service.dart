import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

abstract interface class DriverIdProvider {
  Future<String> getOrCreate();
}

class DriverIdentityService implements DriverIdProvider {
  DriverIdentityService({
    SharedPreferences? preferences,
    String Function()? uuidGenerator,
  }) : _preferences = preferences == null
           ? SharedPreferences.getInstance()
           : Future.value(preferences),
       _uuidGenerator = uuidGenerator ?? const Uuid().v4;

  static const storageKey = 'driver_id';

  final Future<SharedPreferences> _preferences;
  final String Function() _uuidGenerator;

  @override
  Future<String> getOrCreate() async {
    final preferences = await _preferences;
    final stored = preferences.getString(storageKey);
    if (stored != null && _isUuidV4(stored)) {
      return stored;
    }

    final generated = _uuidGenerator();
    if (!_isUuidV4(generated)) {
      throw StateError('The UUID generator must return a UUID v4.');
    }
    await preferences.setString(storageKey, generated);
    return generated;
  }

  static bool _isUuidV4(String value) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value);
}
