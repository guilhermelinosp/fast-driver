import 'package:fast_driver/driver_identity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('DriverIdentityService', () {
    test('generates a UUID v4 on first call', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = DriverIdentityService(
        preferences: prefs,
        uuidGenerator: () => 'a1b2c3d4-e5f6-4a7b-8c9d-e1f2a3b4c5d6',
      );

      final id = await service.getOrCreate();
      expect(id, 'a1b2c3d4-e5f6-4a7b-8c9d-e1f2a3b4c5d6');
    });

    test('persists the UUID in shared_preferences', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = DriverIdentityService(
        preferences: prefs,
        uuidGenerator: () => 'a1b2c3d4-e5f6-4a7b-8c9d-e1f2a3b4c5d6',
      );

      await service.getOrCreate();
      expect(
        prefs.getString(DriverIdentityService.storageKey),
        'a1b2c3d4-e5f6-4a7b-8c9d-e1f2a3b4c5d6',
      );
    });

    test('returns stored UUID on second call without regenerating', () async {
      final prefs = await SharedPreferences.getInstance();
      final stored = 'a1b2c3d4-e5f6-4a7b-8c9d-e1b2c3d4e5f6';
      await prefs.setString(DriverIdentityService.storageKey, stored);

      var callCount = 0;
      final service = DriverIdentityService(
        preferences: prefs,
        uuidGenerator: () {
          callCount++;
          return 'b2c3d4e5-f6a7-4b8c-9d0e-f1a2b3c4d5e6';
        },
      );

      final id = await service.getOrCreate();
      expect(id, stored);
      expect(callCount, 0);
    });

    test('regenerates UUID when stored value is not a valid v4 UUID', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(DriverIdentityService.storageKey, 'invalid');

      final service = DriverIdentityService(
        preferences: prefs,
        uuidGenerator: () => 'a1b2c3d4-e5f6-4a7b-8c9d-e1a2b3c4d5e6',
      );

      final id = await service.getOrCreate();
      expect(id, 'a1b2c3d4-e5f6-4a7b-8c9d-e1a2b3c4d5e6');
      expect(
        prefs.getString(DriverIdentityService.storageKey),
        'a1b2c3d4-e5f6-4a7b-8c9d-e1a2b3c4d5e6',
      );
    });

    test('regenerates UUID when stored value is a non-v4 UUID', () async {
      final prefs = await SharedPreferences.getInstance();
      // UUID v1 format (starts with 1, not 4 in the variant field)
      await prefs.setString(
        DriverIdentityService.storageKey,
        'a1b2c3d4-e5f6-1a7b-8c9d-e1a2b3c4d5e6',
      );

      final service = DriverIdentityService(
        preferences: prefs,
        uuidGenerator: () => 'a1b2c3d4-e5f6-4a7b-8c9d-e1a2b3c4d5e6',
      );

      final id = await service.getOrCreate();
      expect(id, 'a1b2c3d4-e5f6-4a7b-8c9d-e1a2b3c4d5e6');
    });

    test('overwrites invalid stored UUID with generated one', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(DriverIdentityService.storageKey, 'not-a-uuid');

      final service = DriverIdentityService(
        preferences: prefs,
        uuidGenerator: () => 'a1b2c3d4-e5f6-4a7b-8c9d-e1a2b3c4d5e6',
      );

      await service.getOrCreate();
      expect(
        prefs.getString(DriverIdentityService.storageKey),
        'a1b2c3d4-e5f6-4a7b-8c9d-e1a2b3c4d5e6',
      );
    });

    test('throws StateError when UUID generator returns non-v4', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = DriverIdentityService(
        preferences: prefs,
        uuidGenerator: () => 'not-a-uuid',
      );

      await expectLater(service.getOrCreate(), throwsA(isA<StateError>()));
    });

    test('case-insensitive v4 UUID is accepted', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = DriverIdentityService(
        preferences: prefs,
        uuidGenerator: () => 'A1B2C3D4-E5F6-4A7B-8C9D-E1A2B3C4D5E6',
      );

      final id = await service.getOrCreate();
      expect(id, 'A1B2C3D4-E5F6-4A7B-8C9D-E1A2B3C4D5E6');
    });
  });
}
