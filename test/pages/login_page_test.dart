import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pmis_deped/database/database_helper.dart';
import 'package:pmis_deped/pages/login_page.dart';
import 'package:pmis_deped/services/app_state.dart';
import 'package:pmis_deped/services/login_credentials_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmpDir = Directory.systemTemp.createTempSync('pmis_login_page_test_');
    await DatabaseHelper.initForTests(
      dbPath: p.join(tmpDir.path, 'pmis_login_page_test.db'),
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

  testWidgets('shows error when credentials are empty', (tester) async {
    final appState = AppState();
    await tester.pumpWidget(MaterialApp(home: LoginPage(appState: appState)));

    final loginBtn = find.text('Login');
    expect(loginBtn, findsOneWidget);
    await tester.tap(loginBtn);
    await tester.pump();

    expect(
      find.text('Please enter your username and password.'),
      findsOneWidget,
    );
  });

  testWidgets('shows error when credentials are invalid', (tester) async {
    final appState = AppState();
    await tester.pumpWidget(MaterialApp(home: LoginPage(appState: appState)));

    await tester.enterText(find.byType(TextField).first, 'wrong');
    await tester.enterText(find.byType(TextField).at(1), 'wrong');
    await tester.tap(find.text('Login'));
    await _pumpUntilVisible(tester, find.text('Invalid username or password.'));

    expect(find.text('Invalid username or password.'), findsOneWidget);
  });

  testWidgets('navigates to dashboard on valid credentials', (tester) async {
    final appState = AppState();

    final obs = _RecordingObserver();
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(appState: appState),
        navigatorObservers: [obs],
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'admin');
    await tester.enterText(find.byType(TextField).at(1), 'admin');

    await tester.tap(find.text('Login'));
    await _pumpUntil(() => obs.didReplaceCalled, tester);

    expect(obs.didReplaceCalled, isTrue);
    expect(appState.currentActorName, 'admin');
    expect(find.text('Role'), findsNothing);
  });

  testWidgets('login uses the latest externally reset password', (
    tester,
  ) async {
    final appState = AppState();
    await appState.setLoginCredentials(username: 'admin', password: 'oldPass1');
    await LoginCredentialsStore.save(
      LoginCredentials(
        username: 'admin',
        passwordHash: LoginCredentialsStore.hashPassword('newPass2'),
      ),
    );

    final obs = _RecordingObserver();
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(appState: appState),
        navigatorObservers: [obs],
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'admin');
    await tester.enterText(find.byType(TextField).at(1), 'oldPass1');
    await tester.tap(find.text('Login'));
    await _pumpUntilVisible(tester, find.text('Invalid username or password.'));

    expect(find.text('Invalid username or password.'), findsOneWidget);
    expect(obs.didReplaceCalled, isFalse);

    await tester.enterText(find.byType(TextField).at(1), 'newPass2');
    await tester.tap(find.text('Login'));
    await _pumpUntil(() => obs.didReplaceCalled, tester);

    expect(obs.didReplaceCalled, isTrue);
    expect(appState.currentActorName, 'admin');
  });
}

class _RecordingObserver extends NavigatorObserver {
  bool didReplaceCalled = false;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    didReplaceCalled = true;
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  int maxAttempts = 40,
}) async {
  await _pumpUntil(() => finder.evaluate().isNotEmpty, tester, maxAttempts);
}

Future<void> _pumpUntil(
  bool Function() condition,
  WidgetTester tester, [
  int maxAttempts = 40,
]) async {
  for (var i = 0; i < maxAttempts; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) {
      return;
    }
  }

  fail('Condition not met within the allotted pump attempts.');
}
