# PMIS DepED

Personnel Management Information System for DepEd SGOD, built as a Windows desktop Flutter application.

## Scope

- Platform: Windows desktop only
- Storage: Local SQLite database with local snapshot archives
- Primary modules:
  - Dashboard
  - WFP Management
  - Budget Overview
  - Reports
  - Deadlines
  - Settings / Backups
  - Audit Log
  - Recycle Bin

## Recent Improvements

- Deadline queries now include overdue WFPs and activities, not just upcoming ones.
- Manual archives now use SQLite snapshotting for safer backups while the database is open.
- Auto-backup delay and retention are now persisted across launches.
- WFP and activity validation is stricter around duplicates, dates, and invalid values.
- Report preview now uses the configured operating unit consistently.
- Audit log entries now record the acting user for each change, with admin access assumed for the single-user desktop setup.
- Login now uses local credentials with a default `admin` / `admin` account, and credentials can be changed from Settings after confirming the current username and password.
- Offline fallback now restores cached WFPs, activities, recycle-bin state, audit history, and deadline summaries when the database is unavailable.
- Deadline cards can now open the exact WFP or activity record directly.
- Named filter presets are now available in WFP Management, Budget Overview, Reports, and Recycle Bin.
- Windows desktop reminders can now notify users about urgent deadline items while the app is running.
- Bulk Excel import now supports template download, preview validation, and rollback snapshots before import.
- Report filters are remembered between sessions.
- Dashboard aggregation was refactored into a dedicated snapshot helper to reduce rebuild-time work.
- The dashboard greeting now shows the signed-in username.

## Development

### Requirements

- Flutter SDK
- Windows desktop support enabled

### Run locally

```bash
flutter pub get
flutter run -d windows
```

### Test

```bash
flutter test
```

## Login

- Default username: `admin`
- Default password: `admin`
- Credentials can be changed in Settings after entering the current username and password.
- Login credentials are now stored in `%LOCALAPPDATA%\PMIS DepED\login_credentials.json`.

## Password Reset Utility

- A standalone Windows utility is available in [password_reset_utility/README.md](/c:/Users/RicFrancis/OneDrive/Documents/EMSWorkstation/DepedPIMS/password_reset_utility/README.md).
- The utility generates a new alphanumeric password with one button click.
- It updates the same shared credential file used by the main PMIS desktop app, so it works even when the main app is closed.

## Data and Backups

- The live database is stored in `%LOCALAPPDATA%\PMIS DepED\pmis_deped.db`.
- Snapshot archives are stored in `%LOCALAPPDATA%\PMIS DepED\archives\`.
- Auto-backups are stored in `%LOCALAPPDATA%\PMIS DepED\archives\auto\`.
- Restore creates a pre-restore snapshot before replacing the live database.
- Bulk workbook imports also create a rollback snapshot before any records are written.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the current implementation roadmap and next-phase backlog.
