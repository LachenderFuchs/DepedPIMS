import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pmis_deped/database/database_helper.dart';
import 'package:pmis_deped/services/login_credentials_store.dart';
import 'package:pmis_deped/services/password_reset_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmpDir = Directory.systemTemp.createTempSync('pmis_password_reset_test_');
    await DatabaseHelper.initForTests(
      dbPath: p.join(tmpDir.path, 'pmis_password_reset_test.db'),
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

  test('generatePassword always includes letters and digits', () {
    final password = PasswordResetService.generatePassword(length: 14);

    expect(password, hasLength(14));
    expect(RegExp(r'[A-Z]').hasMatch(password), isTrue);
    expect(RegExp(r'[a-z]').hasMatch(password), isTrue);
    expect(RegExp(r'[0-9]').hasMatch(password), isTrue);
    expect(RegExp(r'^[A-Za-z0-9]+$').hasMatch(password), isTrue);
  });

  test(
    'resetPassword keeps username and updates the stored password hash',
    () async {
      await LoginCredentialsStore.save(
        LoginCredentials(
          username: 'manager',
          passwordHash: LoginCredentialsStore.hashPassword('oldPassword1'),
        ),
      );

      final result = await PasswordResetService.resetPassword(length: 16);
      final stored = await LoginCredentialsStore.load(
        allowLegacyMigration: false,
      );

      expect(result.username, 'manager');
      expect(result.generatedPassword, hasLength(16));
      expect(
        stored.passwordHash,
        LoginCredentialsStore.hashPassword(result.generatedPassword),
      );
      expect(stored.username, 'manager');
    },
  );
}
