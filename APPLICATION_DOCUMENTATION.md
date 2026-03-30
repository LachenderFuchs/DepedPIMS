# PMIS DepED Application Documentation

## 1. Overview

PMIS DepED is a Flutter-based Windows desktop application for managing Work and Financial Plan (WFP) records, related budget activities, report exports, deadlines, archives, audit history, and recovery workflows for DepEd SGOD operations.

The application is designed as a local-first desktop system:

- Platform: Windows desktop only
- Database: local SQLite
- State layer: in-memory `AppState` with SharedPreferences-backed fallback cache
- Primary data domains: WFPs, budget activities, audit history, recycle bin, backups, deadlines, report exports, bulk imports

The current roadmap for the Windows version is complete. Remaining work is listed in the backlog section of this document.

## 2. Goals and Scope

The application is intended to help staff:

- create and maintain WFP records
- track fund allocations, obligations, disbursements, and balances
- manage activity-level spending under approved WFPs
- monitor due dates and overdue items
- export operational and financial reports to Excel and PDF
- recover from mistakes using archives and a recycle bin
- trace record changes through an audit log

This codebase currently targets a single-machine Windows deployment. It does not implement remote sync, cloud storage, or a centralized authentication backend.

## 3. Platform and Technical Stack

### Framework and language

- Flutter
- Dart

### Key packages

- `provider`: state propagation
- `sqflite_common_ffi`: SQLite access on Windows
- `shared_preferences`: local settings and fallback cache
- `window_manager`: desktop window sizing and focus control
- `local_notifier`: Windows desktop reminders
- `excel`: Excel import and export
- `pdf`: PDF report generation
- `file_picker`: template save and workbook selection
- `crypto`: local password hashing for stored login credentials
- `path_provider` and `path`: file system paths and output locations
- `data_table_2`: large tabular data presentation
- `intl`: formatting support
- `uuid`: utility support

## 4. Runtime Architecture

### Startup flow

At application launch:

1. Flutter bindings and desktop window management are initialized.
2. Local notification support is initialized for Windows reminders.
3. `AppState` is created and loaded.
4. `DeadlineReminderService` is attached to the shared `AppState`.
5. persisted auto-backup settings are loaded
6. a startup auto-backup is scheduled using the current backup delay
7. the app opens on the login screen

### Main architectural layers

- `lib/main.dart`
  - desktop startup, theme wiring, root app creation
- `lib/services/app_state.dart`
  - central state store and orchestration layer
- `lib/database/database_helper.dart`
  - SQLite schema, CRUD, archive creation, restore, audit persistence, recycle bin persistence
- `lib/models/*.dart`
  - domain models for WFPs and activities
- `lib/pages/*.dart`
  - user-facing screens
- `lib/services/*.dart`
  - exports, reminders, dashboard aggregation, presets, imports
- `lib/widgets/*.dart`
  - shared UI components
- `lib/utils/*.dart`
  - validation, formatting, and ID helpers

### State management

`AppState` is the shared in-memory state container for the application. It is responsible for:

- loading the database at startup
- caching key entities in memory
- persisting settings such as operating unit, warning days, and currency symbol
- persisting local login credentials for the single-machine sign-in flow through a shared credential file in `%LOCALAPPDATA%\PMIS DepED\`
- providing fallback behavior if the database becomes unavailable
- coordinating CRUD actions with audit logging and cache refresh
- exposing derived counts such as deadline warnings and recycle bin totals

## 5. User-Facing Modules

### Login

The application starts on `LoginPage`.

Current behavior:

- the login screen requires a locally stored username and password
- default credentials are `admin` / `admin`
- credentials are validated against values stored in the shared `login_credentials.json` file
- the stored password is hashed before persistence
- successful login creates an in-app session in `AppState`
- the session actor is used for dashboard greeting text, audit metadata, and sidebar display
- a reminder check is triggered after login

Current scope:

- this is a local, single-account sign-in flow for one machine
- there is no remote identity provider, multi-user directory, or role matrix
- a separate Windows password reset utility can generate and apply a new password without requiring the main PMIS app to be open

### Dashboard

The dashboard provides an at-a-glance summary of the system and uses the extracted `DashboardSnapshot` helper to reduce rebuild cost.

It summarizes:

- total budget across visible WFPs
- total disbursed amounts across activities
- total balance
- activity counts
- fund-type distribution
- fiscal-year-based views
- deadline previews

The dashboard uses centralized aggregation instead of recalculating large summary sets repeatedly inside the page widget tree.

### WFP Management

The WFP Management module is the main entry point for WFP records.

Core capabilities:

- create WFP entries
- edit existing WFP entries
- search, sort, and paginate WFP records
- filter and save named filter presets
- select a WFP for downstream activity management
- soft-delete WFPs into the recycle bin
- open a WFP directly from deadline flows

WFP section support:

- HRD
- SMME
- PRS
- YFB
- SHNS
- EFS
- SMNS
- Sports

### Budget Overview

This module manages budget activities under the selected WFP.

Core capabilities:

- display parent WFP information
- add, edit, and soft-delete activities
- compute total, projected, disbursed, and balance values
- search, sort, and paginate activity rows
- save and restore named filter presets
- restore deleted activity records through the recycle bin flow

Activities are tied to a parent WFP and are expected to fit within the WFP ceiling.

### Reports

The Reports module is used for export workflows.

Supported export behaviors:

- Excel summary report for a single WFP
- PDF summary report for a single WFP
- grouped Excel export for multiple WFPs
- grouped PDF export for multiple WFPs
- export based on current filters
- grouped export by year
- grouped export by fund type
- grouped export by month

The module also supports:

- search, sort, and pagination
- named filter presets
- persisted report filters between sessions

The configured operating unit name is used consistently in report output and preview text.

### Deadlines

The Deadlines module shows upcoming and overdue due dates for:

- WFP due dates
- budget activity target dates

Behavior:

- overdue items are included, not just future items
- day calculations are normalized to date-only comparisons
- deadline cards can open the exact WFP or activity record
- the sidebar shows a badge with the current warning count

### Settings

The Settings module centralizes operational configuration and maintenance tasks.

Current areas covered:

- local login credential management
- operating unit name
- currency symbol
- warning-day threshold for deadline badges
- reminder settings
- archive and backup controls
- archive browsing, validation, restore, and deletion
- bulk import template generation
- workbook preview and import execution
- recycle bin access

This page also displays backup status and allows manual reminder checks.

### Audit Log

The Audit Log records data changes to WFPs and activities.

Tracked actions include:

- create
- update
- delete
- restore

The UI supports:

- search
- readable field-diff presentation
- actor display
- browsing recent change history

The actor shown in the audit log comes from the current app session.

### Recycle Bin

The Recycle Bin stores soft-deleted items before permanent removal.

Current support:

- WFP restore
- activity restore
- permanent deletion of individual entries
- empty recycle bin
- search
- sort controls
- named filter presets

For WFP deletions, the recycle bin stores both the WFP snapshot and its related activities.

## 6. Core Domain Model

### WFPEntry

`WFPEntry` represents a work and financial plan record.

Fields:

| Field | Type | Description |
| --- | --- | --- |
| `id` | `String` | Unique WFP ID |
| `title` | `String` | Program or WFP title |
| `targetSize` | `String` | Target size or target count |
| `indicator` | `String` | Indicator or details text |
| `year` | `int` | Fiscal/calendar year stored with the record |
| `fundType` | `String` | Source/type of fund |
| `viewSection` | `String` | Section/division tag |
| `amount` | `double` | WFP budget ceiling |
| `approvalStatus` | `String` | `Pending`, `Approved`, or `Rejected` |
| `approvedDate` | `String?` | ISO date string when approved |
| `dueDate` | `String?` | ISO date string for deadline tracking |

Derived behavior:

- `isApproved` returns whether the WFP is explicitly approved
- `daysUntilDue` returns the number of days until or past the due date

### BudgetActivity

`BudgetActivity` represents a budget-spending activity under a parent WFP.

Fields:

| Field | Type | Description |
| --- | --- | --- |
| `id` | `String` | Unique activity ID |
| `wfpId` | `String` | Parent WFP ID |
| `name` | `String` | Activity name |
| `total` | `double` | Total allocated amount |
| `projected` | `double` | Projected or obligated amount |
| `disbursed` | `double` | Actual disbursed amount |
| `status` | `String` | Current activity status |
| `targetDate` | `String?` | ISO date string for deadline tracking |

Derived behavior:

- `balance` returns `total - disbursed`
- `daysUntilTarget` returns the number of days until or past the target date

### ID generation rules

The app generates IDs using helper methods in `IDGenerator`.

- WFP format: `WFP-<year>-<4 digit sequence>`
- Activity format: `ACT-<wfpId>-<2 digit sequence>`

Examples:

- `WFP-2026-0001`
- `ACT-WFP-2026-0001-01`

## 7. Database Design

The live SQLite database file is stored in `%LOCALAPPDATA%\PMIS DepED\pmis_deped.db`.

Current schema version: `8`

### Table: `wfp`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `TEXT PRIMARY KEY` | WFP ID |
| `title` | `TEXT NOT NULL` | Title |
| `targetSize` | `TEXT NOT NULL` | Target size |
| `indicator` | `TEXT NOT NULL` | Indicator/details |
| `year` | `INTEGER NOT NULL` | Year |
| `fundType` | `TEXT NOT NULL` | Fund type |
| `viewSection` | `TEXT NOT NULL DEFAULT 'HRD'` | Section |
| `amount` | `REAL NOT NULL` | Budget amount |
| `approvalStatus` | `TEXT NOT NULL DEFAULT 'Pending'` | Approval state |
| `approvedDate` | `TEXT` | Approval date |
| `dueDate` | `TEXT` | Due date |

### Table: `activities`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `TEXT PRIMARY KEY` | Activity ID |
| `wfpId` | `TEXT NOT NULL` | Parent WFP ID |
| `name` | `TEXT NOT NULL` | Activity name |
| `total` | `REAL NOT NULL` | Total amount |
| `projected` | `REAL NOT NULL` | Projected/obligated amount |
| `disbursed` | `REAL NOT NULL` | Disbursed amount |
| `status` | `TEXT NOT NULL` | Status |
| `targetDate` | `TEXT` | Target date |

Relationship:

- `activities.wfpId` references `wfp.id`

### Table: `audit_log`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `INTEGER PRIMARY KEY AUTOINCREMENT` | Row ID |
| `entityType` | `TEXT NOT NULL` | `WFP` or `Activity` |
| `entityId` | `TEXT NOT NULL` | Target record ID |
| `action` | `TEXT NOT NULL` | Create/update/delete/restore |
| `actorName` | `TEXT NOT NULL` | Session user name |
| `actorRole` | `TEXT NOT NULL` | Internal compatibility field, currently stored as `Admin` |
| `actorComment` | `TEXT` | Optional context such as bulk import source |
| `timestamp` | `TEXT NOT NULL` | ISO timestamp |
| `diffJson` | `TEXT NOT NULL` | JSON snapshot or field diff |

### Table: `recycle_bin`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `INTEGER PRIMARY KEY AUTOINCREMENT` | Bin entry ID |
| `entryType` | `TEXT NOT NULL DEFAULT 'WFP'` | `WFP` or activity entry |
| `wfpJson` | `TEXT NOT NULL DEFAULT ''` | Serialized WFP snapshot |
| `activitiesJson` | `TEXT NOT NULL DEFAULT '[]'` | Serialized activity list for WFP deletes |
| `activityJson` | `TEXT` | Serialized single activity snapshot |
| `wfpId` | `TEXT` | Parent WFP reference for activity deletes |
| `deletedAt` | `TEXT NOT NULL` | Deletion timestamp |

## 8. Persistence, Backup, and Recovery

### Live database location

- file name: `pmis_deped.db`
- location: `%LOCALAPPDATA%\PMIS DepED\`

### Archive locations

- manual archives: `%LOCALAPPDATA%\PMIS DepED\archives\`
- auto-backups: `%LOCALAPPDATA%\PMIS DepED\archives\auto\`

Both archive folders are created under the shared app-data directory as needed.

### Snapshot strategy

The app uses SQLite snapshot creation with `VACUUM INTO` instead of raw file copy for backup generation. This is safer while the database is open.

### Auto-backup behavior

Auto-backup characteristics:

- default delay: 30 seconds
- default retention: 5 auto-backups
- delay is debounced after writes
- only one backup is produced per burst of write activity
- settings persist across launches
- backup status is surfaced in Settings

### Startup recovery

When the app opens, it checks whether the live database:

- exists
- is large enough to be valid
- passes SQLite `PRAGMA integrity_check`

If the main database is invalid, the app scans both manual and auto archive folders and restores the newest valid archive before continuing.

### Restore behavior

When restoring from a selected archive:

- the archive is validated first
- a pre-restore backup of the current live database is created
- the selected archive replaces the live database
- the restored result is validated again
- if validation fails, the pre-restore backup is copied back

### Bulk import rollback protection

Before a bulk import writes records:

- a rollback archive is created
- records are inserted
- audit entries are written
- if any failure occurs, the rollback archive is restored

## 9. Offline and Fallback Behavior

If the database becomes unavailable during startup or runtime, the app falls back to locally cached content stored in SharedPreferences.

Cached areas currently include:

- WFP list
- activity list
- recycle bin entries
- audit log entries

Additional fallback behavior:

- deadline lists can be recomputed locally from cached records
- filtered exports can use cached in-memory data when database reads fail
- selected WFP activity lists can fall back to the cached all-activities list

This is a resilience layer, not a multi-device sync system.

## 10. Validation Rules

Validation logic is centralized in `RecordValidator`.

### WFP validation

Current rules:

- title cannot be empty
- target size cannot be empty
- indicator cannot be empty
- amount must be numeric
- amount cannot be negative
- approved date must be valid if provided
- due date must be valid if provided
- approved WFPs must include an approved date
- due date cannot be earlier than approved date
- duplicate WFPs are blocked when title, year, fund type, and section match

### Activity validation

Current rules:

- parent WFP must already be approved
- name cannot be empty
- total, projected, and disbursed must be numeric
- amounts cannot be negative
- duplicate activity names under the same WFP are blocked
- total activity amounts cannot exceed the parent WFP ceiling
- target date must be valid if provided
- target date cannot be earlier than the parent WFP approved date
- target date cannot be later than the parent WFP due date

## 11. Deadline and Reminder System

### Deadline tracking

Deadlines are based on:

- `WFPEntry.dueDate`
- `BudgetActivity.targetDate`

`AppState` maintains:

- the warning-day threshold
- the current due-soon WFP list
- the current due-soon activity list
- the total warning badge count

### Reminder service

`DeadlineReminderService` is responsible for in-app Windows notifications while the application is running.

Default reminder settings:

- enabled: `true`
- interval: `60` minutes
- urgency threshold: `1` day

Reminder behavior:

- reminders only run when an active session exists
- reminders scan due-soon and overdue items
- already-seen reminders are suppressed for the rest of the day unless forced
- clicking a reminder focuses the app window

Current limitation:

- clicking a reminder focuses the app, but does not yet deep-link into the exact record

## 12. Reporting

### Single-record exports

The app can export a single WFP and its activities as:

- Excel summary report
- PDF summary report

Report content includes:

- operating unit
- fund type
- WFP title
- indicator
- approval status
- due date when present
- activity table
- totals for AR, projected/obligated, disbursed, and balance

### Grouped exports

The app can export grouped sets of WFPs in a single document:

- grouped Excel export
- grouped PDF export

Grouping options exposed in the UI:

- by year
- by fund type
- by month
- all currently filtered entries

### Export output location

Reports are written to the Windows application documents directory returned by `path_provider`.

File naming patterns:

- `SummaryReport_<WFP_ID>_<safe_title>.xlsx`
- `GroupedReport_<label>_<timestamp>.xlsx`
- `SummaryReport_<WFP_ID>.pdf`
- `GroupedReport_<label>.pdf`

## 13. Bulk Import

Bulk import is handled by `BulkImportService`.

### Workbook structure

Supported workbook sheets:

- `WFP`
- `Activities`
- `Instructions`

### WFP columns accepted

- WFP ID
- Title
- Target Size
- Indicator
- Year
- Fund Type
- Section
- Amount
- Approval Status
- Approved Date
- Due Date

### Activity columns accepted

- Activity ID
- Parent WFP ID
- Name
- Total AR
- Projected / Obligated
- Disbursed
- Status
- Target Date

### Import behavior

The import workflow supports:

- template generation
- workbook picking from disk
- preview row display
- error and warning detection before import
- validation against current live data
- duplicate ID checks
- parent-child consistency checks
- rollback snapshot before committing data

If an import succeeds, created records are also written to the audit log with bulk-import context.

## 14. Audit Logging

Audit logging is integrated into major data-changing operations.

When the app writes a WFP or activity, it logs:

- entity type
- entity ID
- action
- actor name
- internal admin marker
- optional actor comment
- timestamp
- field snapshot or field diff JSON

Examples of actor metadata sources:

- current session username
- fixed admin role marker
- import-specific comment such as workbook source

Current limitation:

- the app stores actor identity from the locally verified sign-in flow, not from an external identity provider

## 15. Recycle Bin Behavior

The recycle bin is a soft-delete safety layer.

### WFP deletion

Deleting a WFP:

- captures the WFP as serialized JSON
- captures all related activities as serialized JSON
- stores the deletion timestamp
- removes the live rows from the active tables

### Activity deletion

Deleting an activity:

- captures the activity snapshot as JSON
- stores the parent WFP ID for context
- removes the activity from the live table

### Restore rules

Restore safeguards include:

- WFP restore is blocked if the live WFP ID already exists
- activity restore is blocked if the parent WFP is missing or the activity ID conflicts

## 16. Filter Presets and Shared UX Helpers

Named filter presets are implemented through `FilterPresetStore` and `FilterPresetBar`.

Current pages using named presets:

- WFP Management
- Budget Overview
- Reports
- Recycle Bin

Preset storage:

- stored in SharedPreferences
- saved per logical scope key
- overwrite is based on preset name matching within the same scope

Other shared UX helpers include:

- `BrandMark`
- `Hint`
- `PaginationBar`
- `ResponsiveLayout`
- `SettingsSectionCard`
- `Sidebar`

## 17. File and Folder Guide

### Root

- `README.md`: project overview and basic run instructions
- `ROADMAP.md`: completed Windows roadmap and remaining backlog
- `pubspec.yaml`: package configuration

### `lib/`

- `main.dart`: app bootstrap
- `theme/app_theme.dart`: global theme

### `lib/models/`

- `wfp_entry.dart`
- `budget_activity.dart`

### `lib/database/`

- `database_helper.dart`: SQLite and backup/recovery logic

### `lib/services/`

- `app_state.dart`: shared state and orchestration
- `dashboard_snapshot.dart`: dashboard aggregation helper
- `deadline_reminder_service.dart`: Windows reminder scheduler
- `bulk_import_service.dart`: template generation and workbook preview/import
- `filter_preset_store.dart`: saved presets
- `report_exporter.dart`: Excel export
- `pdf_exporter.dart`: PDF export

### `lib/pages/`

- `login_page.dart`
- `dashboard_page.dart`
- `wfp_management_page.dart`
- `budget_overview_page.dart`
- `reports_page.dart`
- `deadlines_page.dart`
- `settings_page.dart`
- `audit_log_page.dart`
- `recycle_bin_page.dart`

### `lib/widgets/`

- `brand_mark.dart`
- `sidebar.dart`
- `summary_card.dart`
- `pagination_bar.dart`
- `filter_preset_bar.dart`
- `hint.dart`
- `form_field.dart`
- `import_preview_dialog.dart`
- `settings_section_card.dart`
- `responsive_layout.dart`
- form and hint widgets

### `lib/utils/`

- `record_validator.dart`
- `id_generator.dart`
- `currency_formatter.dart`
- `decimal_input_formatter.dart`

## 18. Settings and Defaults

Current defaults in the codebase include:

- operating unit: `Department of Education`
- currency symbol: Philippine peso symbol
- warning days: `7`
- auto-backup delay: `30 seconds`
- auto-backup retention: `5`
- reminder enabled: `true`
- reminder interval: `60 minutes`
- reminder urgency threshold: `1 day`
- login username: `admin`
- login password: `admin`
- session access mode: `Admin`

Note:

- the UI uses the peso symbol as the intended default currency even though terminal output or encoded file reads may display it differently depending on character encoding

## 19. Testing and Verification

The project includes:

- `flutter_test`
- `integration_test`

The current codebase has coverage added for important workflows such as:

- deadline queries
- backup-setting persistence
- validation behavior
- audit log behavior
- login/session flow
- filter preset persistence
- bulk import service behavior

Standard verification commands:

```bash
flutter analyze
flutter test
```

## 20. Current Limitations

The application is fully usable as a Windows local desktop system, but some areas are intentionally still simple or local-only.

Known limitations:

- authentication is local-only and single-account
- credential storage is machine-local and uses a local password hash, not a remote identity service
- reminder notifications focus the app window but do not yet deep-link into the specific record
- no cloud sync or centralized multi-user backend exists
- persistence is machine-local
- some large edit pages can still be decomposed further

## 21. Backlog After the Completed Windows Roadmap

Remaining backlog items already identified in the project roadmap:

1. Audit log action reasons and approval comments
2. Deadline reminder actions that deep-link directly into the target record
3. Import/export templates for more report shapes
4. More decomposition of complex edit forms into smaller widgets and controllers

## 22. Summary

PMIS DepED is now a Windows-focused, local-first operations tool with:

- WFP and activity lifecycle management
- resilient local SQLite storage
- safer archive and restore workflows
- audit accountability
- local credential validation with in-app credential management
- recycle bin recovery
- Excel and PDF exports
- bulk import with preview and rollback
- overdue-aware deadline monitoring
- Windows reminder notifications
- saved filter presets and shared desktop UI helpers

For a quick project summary, see `README.md`. For implementation history and next-phase work, see `ROADMAP.md`.
