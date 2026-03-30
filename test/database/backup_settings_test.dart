import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pmis_deped/database/database_helper.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'loadBackupSettings restores persisted backup delay and retention',
    () async {
      SharedPreferences.setMockInitialValues({
        'autoBackupDelaySeconds': 900,
        'autoBackupRetentionCount': 10,
      });

      await DatabaseHelper.loadBackupSettings();

      expect(DatabaseHelper.autoBackupDelay, const Duration(minutes: 15));
      expect(DatabaseHelper.autoBackupRetention, 10);
    },
  );

  test('backup setters persist the selected values', () async {
    await DatabaseHelper.setAutoBackupDelay(const Duration(minutes: 30));
    await DatabaseHelper.setAutoBackupRetention(20);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('autoBackupDelaySeconds'), 1800);
    expect(prefs.getInt('autoBackupRetentionCount'), 20);
  });
}
