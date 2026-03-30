import 'dart:math';

import 'login_credentials_store.dart';

class PasswordResetResult {
  const PasswordResetResult({
    required this.username,
    required this.generatedPassword,
  });

  final String username;
  final String generatedPassword;
}

class PasswordResetService {
  static const String _lowercase = 'abcdefghijkmnopqrstuvwxyz';
  static const String _uppercase = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  static const String _digits = '23456789';
  static const String _allCharacters = _lowercase + _uppercase + _digits;

  static Future<PasswordResetResult> resetPassword({int length = 12}) async {
    if (length < 8) {
      throw ArgumentError('Password length must be at least 8 characters.');
    }

    final existingCredentials = await LoginCredentialsStore.load();
    final generatedPassword = generatePassword(length: length);

    await LoginCredentialsStore.save(
      LoginCredentials(
        username: existingCredentials.username,
        passwordHash: LoginCredentialsStore.hashPassword(generatedPassword),
      ),
    );

    return PasswordResetResult(
      username: existingCredentials.username,
      generatedPassword: generatedPassword,
    );
  }

  static String generatePassword({int length = 12, Random? random}) {
    if (length < 8) {
      throw ArgumentError('Password length must be at least 8 characters.');
    }

    final source = random ?? Random.secure();
    final characters = <String>[
      _pick(_lowercase, source),
      _pick(_uppercase, source),
      _pick(_digits, source),
    ];

    while (characters.length < length) {
      characters.add(_pick(_allCharacters, source));
    }

    characters.shuffle(source);
    return characters.join();
  }

  static String _pick(String alphabet, Random random) {
    return alphabet[random.nextInt(alphabet.length)];
  }
}
