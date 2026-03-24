import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/login_page.dart';
import 'services/app_state.dart';
import 'database/database_helper.dart';
import 'theme/app_theme.dart';

void main() async {
  // Required before any async work or plugin initialization.
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const WindowOptions windowOptions = WindowOptions(
    size: Size(1280, 800),         // default launch size
    minimumSize: Size(1000, 700),  // prevents pixel overflow on resize
    center: true,
    title: 'PMIS-SGOD',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // Boot the shared state and pre-load WFP entries from SQLite.
  final appState = AppState();
  await appState.init();

  // Ensure the auto-backup default is the quick 30s window and schedule
  // a startup auto-backup after that delay so users get an early snapshot.
  try {
    // Adjust session delay to the default; this also cancels any previous timer.
    // (Settings UI allows changing this for the session.)
    // ignore: unawaited_futures
    DatabaseHelper.setAutoBackupDelay(const Duration(seconds: 30));
  } catch (_) {}

  // Schedule a one-shot trigger after the configured delay so the app makes
  // an initial consistent snapshot shortly after launch.
  Future.delayed(const Duration(seconds: 30), () async {
    try {
      await DatabaseHelper.triggerAutoBackupNow();
    } catch (_) {}
  });

  runApp(PIMSApp(appState: appState));
}

class PIMSApp extends StatelessWidget {
  final AppState appState;

  const PIMSApp({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PIMS DepED',
      debugShowCheckedModeBanner: false,
      // Use the centrally-defined theme instead of an inline one.
      theme: AppTheme.theme,
      home: LoginPage(appState: appState),
    );
  }
}