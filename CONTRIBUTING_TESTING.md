# Testing and Contribution Guide

This file explains how to run and add tests for the PMIS DepED app, and describes the recommended testing strategy.

**Quick Commands**
- Install dependencies: `flutter pub get`
- Run all tests locally: `flutter test`
- Run a single test file: `flutter test test/path/to/file_test.dart`

**Test Types Used**
- Unit tests: pure Dart logic (models, utils). Located under `test/models` and `test/utils`.
- Widget tests: small UI units (pages/widgets) using `flutter_test`. Located under `test/pages`.
- Database tests: use `sqflite_common_ffi` against a temporary local DB. Located under `test/database`.
- Integration/E2E: future work â€” use `integration_test` for full app flows.

**Database Testing Notes**
- Tests use `DatabaseHelper.initForTests(dbPath: ...)` which opens an isolated sqlite DB via `sqflite_common_ffi`.
- The test DB is created in the system temp directory and cleaned up after the suite (see `test/database/database_helper_test.dart`).
- Keep tests idempotent: create and tear down only the rows you insert, or use a dedicated temp DB per suite.

**Writing New Tests**
1. Put unit tests under `test/<area>/` matching code area (e.g., `test/services`).
2. Prefer small, focused tests that assert one behavior.
3. For widget tests, avoid rendering large app scaffolds â€” use `MaterialApp` and inject a minimal environment. Use `NavigatorObserver` to verify navigation without rendering heavy pages.
4. For database-related tests, call `await DatabaseHelper.initForTests(dbPath: yourPath)` in `setUpAll` and `await DatabaseHelper.closeDatabase()` in `tearDownAll`.

**CI (GitHub Actions)**
- A workflow is included at `.github/workflows/flutter_tests.yml` that runs `flutter test` on `push` and `pull_request` to `main`.

**Best Practices & Tips**
- Mock external dependencies where practical (e.g., network, file system) to keep tests fast and reliable.
- Use `SharedPreferences.setMockInitialValues({})` in tests that exercise settings.
- When a test touches login credentials, prefer `DatabaseHelper.initForTests(...)` as well so the shared credential file is redirected into a temp folder instead of `%LOCALAPPDATA%`.
- Keep tests deterministic: avoid relying on system time where possible. For date logic, inject or compute relative dates in tests.
- Add tests for migrations and upgrade paths when changing DB schema: create DB at older version and run `_onUpgrade` paths.

If you'd like, I can now:
- Expand database coverage (recycle bin, restore, migrations), or
- Add an `integration_test` skeleton and example, or
- Improve CI to run tests on matrix (Flutter channels / OS).
