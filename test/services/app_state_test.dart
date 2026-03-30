import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pmis_deped/database/database_helper.dart';
import 'package:pmis_deped/services/app_state.dart';
import 'package:pmis_deped/services/login_credentials_store.dart';
import 'package:pmis_deped/utils/currency_formatter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmpDir = Directory.systemTemp.createTempSync('pmis_app_state_test_');
    await DatabaseHelper.initForTests(
      dbPath: p.join(tmpDir.path, 'pmis_deped_app_state_test.db'),
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

  test('setCurrencySymbol updates AppState and CurrencyFormatter', () async {
    final s = AppState();
    await s.setCurrencySymbol('PHP');
    expect(s.currencySymbol, 'PHP');
    expect(CurrencyFormatter.symbol, 'PHP');

    // Ensure value persisted in prefs
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('currencySymbol'), 'PHP');
  });

  test('setOperatingUnit trims and persists default when empty', () async {
    final s = AppState();
    await s.setOperatingUnit('  ');
    expect(s.operatingUnit, 'Department of Education');

    await s.setOperatingUnit('  Division X  ');
    expect(s.operatingUnit, 'Division X');
  });

  test(
    'default admin credentials validate and updated credentials persist',
    () async {
      final s = AppState();

      expect(s.loginUsername, 'admin');
      expect(
        s.validateCredentials(username: 'admin', password: 'admin'),
        isTrue,
      );

      s.startSession(username: 'admin');
      await s.setLoginCredentials(username: 'manager', password: 'secret123');

      expect(s.loginUsername, 'manager');
      expect(s.currentActorName, 'manager');
      expect(
        s.validateCredentials(username: 'manager', password: 'secret123'),
        isTrue,
      );
      expect(
        s.validateCredentials(username: 'admin', password: 'admin'),
        isFalse,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('loginUsername'), 'manager');
      expect(prefs.getString('loginPasswordHash'), isNotEmpty);
    },
  );

  test(
    'validateCredentialsFresh picks up an external password reset',
    () async {
      final s = AppState();
      await s.setLoginCredentials(username: 'admin', password: 'oldSecret1');

      await LoginCredentialsStore.save(
        LoginCredentials(
          username: 'admin',
          passwordHash: LoginCredentialsStore.hashPassword('newSecret2'),
        ),
      );

      expect(
        await s.validateCredentialsFresh(
          username: 'admin',
          password: 'newSecret2',
        ),
        isTrue,
      );
      expect(
        await s.validateCredentialsFresh(
          username: 'admin',
          password: 'oldSecret1',
        ),
        isFalse,
      );
    },
  );
}
