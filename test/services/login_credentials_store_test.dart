import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pmis_deped/database/database_helper.dart';
import 'package:pmis_deped/services/login_credentials_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmpDir = Directory.systemTemp.createTempSync('pmis_login_store_test_');
    await DatabaseHelper.initForTests(
      dbPath: p.join(tmpDir.path, 'pmis_login_store_test.db'),
    );
  });

  tearDown(() async {
    await DatabaseHelper.closeDatabase();
    try {
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('load creates default admin credentials when no file exists', () async {
    final credentials = await LoginCredentialsStore.load(
      allowLegacyMigration: false,
    );
    final file = File(await LoginCredentialsStore.credentialsFilePath);

    expect(credentials.username, LoginCredentialsStore.defaultUsername);
    expect(credentials.passwordHash, LoginCredentialsStore.defaultPasswordHash);
    expect(await file.exists(), isTrue);
  });

  test(
    'load migrates legacy shared preferences credentials into file',
    () async {
      SharedPreferences.setMockInitialValues({
        LoginCredentialsStore.legacyPrefsUsernameKey: 'legacy_admin',
        LoginCredentialsStore.legacyPrefsPasswordHashKey:
            LoginCredentialsStore.hashPassword('legacySecret1'),
      });

      final credentials = await LoginCredentialsStore.load();
      final file = File(await LoginCredentialsStore.credentialsFilePath);
      final raw = jsonDecode(await file.readAsString()) as Map;

      expect(credentials.username, 'legacy_admin');
      expect(
        credentials.passwordHash,
        LoginCredentialsStore.hashPassword('legacySecret1'),
      );
      expect(raw['username'], 'legacy_admin');
    },
  );
}
