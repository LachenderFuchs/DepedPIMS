import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/login_page.dart';
import 'services/app_state.dart';
import 'database/database_helper.dart';
import 'services/deadline_reminder_service.dart';
import 'theme/app_theme.dart';

void main() async {
  // Required before any async work or plugin initialization.
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const WindowOptions windowOptions = WindowOptions(
    size: Size(1280, 800), // default launch size
    minimumSize: Size(480, 640), // keep the app usable on smaller screens
    center: true,
    title: 'PMIS-SGOD',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  await localNotifier.setup(
    appName: 'PMIS DepED',
    shortcutPolicy: ShortcutPolicy.requireCreate,
  );

  // Boot the shared state and pre-load WFP entries from SQLite.
  final appState = AppState();
  await appState.init();
  await DeadlineReminderService.instance.attach(appState);

  // Load persisted Windows backup settings before scheduling the first
  // startup snapshot for this session.
  try {
    await DatabaseHelper.loadBackupSettings();
  } catch (_) {}

  Future.delayed(DatabaseHelper.autoBackupDelay, () async {
    try {
      await DatabaseHelper.triggerAutoBackupNow();
    } catch (_) {}
  });

  runApp(PMISApp(appState: appState));
}

class PMISApp extends StatelessWidget {
  final AppState appState;

  const PMISApp({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PMIS DepED',
      debugShowCheckedModeBanner: false,
      // Use the centrally-defined theme instead of an inline one.
      theme: AppTheme.theme,
      home: LoginPage(appState: appState),
    );
  }
}
