# Windows Roadmap

## Completed In This Pass

1. Deadline coverage and navigation
   - Included overdue WFPs and activities in due-soon queries
   - Normalized day-difference calculations to date-only comparisons
   - Added direct navigation from deadline cards to the exact record

2. Backup and recovery hardening
   - Switched manual archives to SQLite snapshot creation
   - Added persisted auto-backup delay and retention settings
   - Added restore validation with pre-restore backup protection

3. Validation and consistency
   - Centralized WFP and activity validation rules
   - Added duplicate, date-order, and amount checks
   - Fixed report preview to use the configured operating unit

4. Offline and resilience
   - Added local cache fallback for WFPs, activities, recycle-bin entries, and audit history
   - Added local deadline recomputation when DB queries are unavailable

5. Refactor and performance
   - Extracted dashboard aggregation into a snapshot helper
   - Removed one dashboard rebuild hotspot caused by repeated WFP lookups
   - Reused the shared pagination widget from Budget Overview

6. Workflow polish
   - Added direct-open behavior for deadline records
   - Persisted report filters between sessions

7. Verification
   - Added tests for deadline queries, backup setting persistence, and record validation

8. Audit accountability
   - Added actor-aware audit logging with username metadata for the single-user admin setup
   - Surfaced actor details in the audit log UI and sidebar session display

9. Saved filters and workflow presets
   - Added named filter presets for WFP Management, Budget Overview, Reports, and Recycle Bin
   - Reused a shared preset bar instead of page-specific preset logic

10. Windows reminders
   - Added configurable desktop reminder scheduling for urgent deadlines
   - Added manual reminder checks from Settings

11. Bulk import and rollback
   - Added Excel template download for WFP and activity import
   - Added workbook preview validation before import
   - Added rollback-protected bulk import using a pre-import snapshot

12. Page decomposition
   - Extracted reusable settings and preset widgets
   - Reduced page-specific duplication across Settings, WFP, Reports, Recycle Bin, and Budget Overview

## Roadmap Status

The current Windows roadmap is complete.

## Future Backlog

1. Audit log action reasons and approval comments
2. Deadline reminder actions that deep-link directly into the target record
3. Import/export templates for more report shapes
4. More decomposition of complex edit forms into smaller widgets and controllers

## Guiding Principle

Prioritize Windows reliability first: resilient local storage, clear recovery paths, efficient large-list views, and workflows that reduce operator clicks.
