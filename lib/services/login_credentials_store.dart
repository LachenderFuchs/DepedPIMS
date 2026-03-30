import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';

class LoginCredentials {
  const LoginCredentials({required this.username, required this.passwordHash});

  final String username;
  final String passwordHash;

  Map<String, dynamic> toJson() => {
    'username': username,
    'passwordHash': passwordHash,
  };
}

class LoginCredentialsStore {
  static const String legacyPrefsUsernameKey = 'loginUsername';
  static const String legacyPrefsPasswordHashKey = 'loginPasswordHash';
  static const String defaultUsername = 'admin';
  static const String _credentialsFileName = 'login_credentials.json';
  static const String _flutterPrefsPrefix = 'flutter.';
  static final String defaultPasswordHash = hashPassword('admin');

  static String hashPassword(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static Future<String> get credentialsFilePath async =>
      p.join(await DatabaseHelper.dataDirectoryPath, _credentialsFileName);

  static Future<LoginCredentials> load({
    bool allowLegacyMigration = true,
  }) async {
    final storedCredentials = await _loadFromFile();
    final legacyCredentials = allowLegacyMigration
        ? await _loadFromLegacyPrefs()
        : null;

    if (_shouldPreferLegacyCredentials(storedCredentials, legacyCredentials)) {
      await save(legacyCredentials!, syncLegacyPrefs: true);
      return legacyCredentials;
    }

    if (storedCredentials != null) {
      return storedCredentials;
    }

    final defaults = LoginCredentials(
      username: defaultUsername,
      passwordHash: defaultPasswordHash,
    );
    await save(defaults, syncLegacyPrefs: allowLegacyMigration);
    return defaults;
  }

  static Future<void> save(
    LoginCredentials credentials, {
    bool syncLegacyPrefs = false,
  }) async {
    final file = File(await credentialsFilePath);
    await file.create(recursive: true);
    await file.writeAsString(jsonEncode(credentials.toJson()));

    if (syncLegacyPrefs) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(legacyPrefsUsernameKey, credentials.username);
      await prefs.setString(
        legacyPrefsPasswordHashKey,
        credentials.passwordHash,
      );
    }
  }

  static Future<LoginCredentials?> _loadFromFile() async {
    try {
      final file = File(await credentialsFilePath);
      if (!await file.exists()) {
        return null;
      }

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return null;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final map = Map<String, dynamic>.from(decoded);

      final username = (map['username'] as String?)?.trim();
      final passwordHash = (map['passwordHash'] as String?)?.trim();
      if (username == null ||
          username.isEmpty ||
          passwordHash == null ||
          passwordHash.isEmpty) {
        return null;
      }

      return LoginCredentials(username: username, passwordHash: passwordHash);
    } catch (_) {
      return null;
    }
  }

  static Future<LoginCredentials?> _loadFromLegacyPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefsCredentials = _credentialsFromMap({
        legacyPrefsUsernameKey: prefs.getString(legacyPrefsUsernameKey),
        legacyPrefsPasswordHashKey: prefs.getString(legacyPrefsPasswordHashKey),
      });
      if (prefsCredentials != null) {
        return prefsCredentials;
      }

      return await _loadFromLegacyWindowsPrefsFile();
    } catch (_) {
      return _loadFromLegacyWindowsPrefsFile();
    }
  }

  static Future<LoginCredentials?> _loadFromLegacyWindowsPrefsFile() async {
    if (!Platform.isWindows) {
      return null;
    }

    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.trim().isEmpty) {
      return null;
    }

    final candidatePaths = [
      p.join(appData, 'com.example', 'PMIS DepED', 'shared_preferences.json'),
      p.join(appData, 'com.example', 'pims_deped', 'shared_preferences.json'),
      p.join(appData, 'com.example', 'pmis_deped', 'shared_preferences.json'),
    ];

    for (final candidatePath in candidatePaths) {
      try {
        final file = File(candidatePath);
        if (!await file.exists()) {
          continue;
        }

        final raw = await file.readAsString();
        if (raw.trim().isEmpty) {
          continue;
        }

        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          continue;
        }

        final credentials = _credentialsFromMap(
          Map<String, dynamic>.from(decoded),
        );
        if (credentials != null) {
          return credentials;
        }
      } catch (_) {}
    }

    return null;
  }

  static LoginCredentials? _credentialsFromMap(Map<String, dynamic> values) {
    final username =
        (values[legacyPrefsUsernameKey] as String?)?.trim() ??
        (values['$_flutterPrefsPrefix$legacyPrefsUsernameKey'] as String?)
            ?.trim();
    final passwordHash =
        (values[legacyPrefsPasswordHashKey] as String?)?.trim() ??
        (values['$_flutterPrefsPrefix$legacyPrefsPasswordHashKey'] as String?)
            ?.trim();
    if (username == null ||
        username.isEmpty ||
        passwordHash == null ||
        passwordHash.isEmpty) {
      return null;
    }

    return LoginCredentials(username: username, passwordHash: passwordHash);
  }

  static bool _shouldPreferLegacyCredentials(
    LoginCredentials? storedCredentials,
    LoginCredentials? legacyCredentials,
  ) {
    if (legacyCredentials == null) {
      return false;
    }
    if (storedCredentials == null) {
      return true;
    }
    if (storedCredentials.username == legacyCredentials.username &&
        storedCredentials.passwordHash == legacyCredentials.passwordHash) {
      return false;
    }

    return _isDefaultCredentials(storedCredentials) &&
        !_isDefaultCredentials(legacyCredentials);
  }

  static bool _isDefaultCredentials(LoginCredentials credentials) {
    return credentials.username == defaultUsername &&
        credentials.passwordHash == defaultPasswordHash;
  }
}
