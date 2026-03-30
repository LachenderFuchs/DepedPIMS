import 'dart:async';
import 'dart:convert';

import 'package:local_notifier/local_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../models/budget_activity.dart';
import '../models/wfp_entry.dart';
import 'app_state.dart';

class DeadlineReminderSettings {
  final bool enabled;
  final int intervalMinutes;
  final int urgencyDays;

  const DeadlineReminderSettings({
    required this.enabled,
    required this.intervalMinutes,
    required this.urgencyDays,
  });

  DeadlineReminderSettings copyWith({
    bool? enabled,
    int? intervalMinutes,
    int? urgencyDays,
  }) {
    return DeadlineReminderSettings(
      enabled: enabled ?? this.enabled,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      urgencyDays: urgencyDays ?? this.urgencyDays,
    );
  }
}

class DeadlineReminderService {
  DeadlineReminderService._();

  static final DeadlineReminderService instance = DeadlineReminderService._();

  static const _enabledKey = 'deadlineReminders.enabled';
  static const _intervalKey = 'deadlineReminders.intervalMinutes';
  static const _urgencyKey = 'deadlineReminders.urgencyDays';
  static const _seenMapKey = 'deadlineReminders.seenByDay';

  AppState? _appState;
  Timer? _timer;
  bool _checking = false;
  DeadlineReminderSettings _settings = const DeadlineReminderSettings(
    enabled: true,
    intervalMinutes: 60,
    urgencyDays: 1,
  );

  DeadlineReminderSettings get settings => _settings;

  Future<void> attach(AppState appState) async {
    _appState = appState;
    _settings = await loadSettings();
    _scheduleTimer();
  }

  Future<DeadlineReminderSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return DeadlineReminderSettings(
      enabled: prefs.getBool(_enabledKey) ?? true,
      intervalMinutes: prefs.getInt(_intervalKey) ?? 60,
      urgencyDays: prefs.getInt(_urgencyKey) ?? 1,
    );
  }

  Future<void> updateSettings(DeadlineReminderSettings settings) async {
    _settings = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, settings.enabled);
    await prefs.setInt(_intervalKey, settings.intervalMinutes);
    await prefs.setInt(_urgencyKey, settings.urgencyDays);
    _scheduleTimer();
  }

  Future<void> checkNow({bool force = false}) async {
    if (_checking) {
      return;
    }
    if (!force && !_settings.enabled) {
      return;
    }
    final appState = _appState;
    if (appState == null || !appState.hasActiveSession) {
      return;
    }

    _checking = true;
    try {
      await appState.refreshDeadlineWarnings();
      final candidates = _buildCandidates(appState);
      if (candidates.isEmpty) {
        return;
      }

      final seenMap = await _loadSeenMap();
      final today = _dateKey(DateTime.now());
      final freshCandidates = candidates
          .where((candidate) {
            if (force) {
              return true;
            }
            return seenMap[candidate.key] != today;
          })
          .toList(growable: false);

      if (freshCandidates.isEmpty) {
        return;
      }

      final title = freshCandidates.any((candidate) => candidate.days < 0)
          ? 'Deadline attention needed'
          : 'Upcoming deadline reminder';
      final body = freshCandidates
          .take(4)
          .map((candidate) => '${candidate.title} (${candidate.statusLabel})')
          .join('\n');

      final notification = LocalNotification(title: title, body: body);
      notification.onClick = () async {
        await windowManager.show();
        await windowManager.focus();
      };
      await notification.show();

      for (final candidate in freshCandidates) {
        seenMap[candidate.key] = today;
      }
      await _saveSeenMap(seenMap);
    } finally {
      _checking = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  List<_ReminderCandidate> _buildCandidates(AppState appState) {
    final candidates = <_ReminderCandidate>[
      ...appState.wfpsDueSoon
          .where((entry) {
            final days = entry.daysUntilDue;
            return days != null && days <= _settings.urgencyDays;
          })
          .map(_fromWfp),
      ...appState.activitiesDueSoon
          .where((activity) {
            final days = activity.daysUntilTarget;
            return days != null && days <= _settings.urgencyDays;
          })
          .map(_fromActivity),
    ];
    candidates.sort((a, b) {
      if (a.days != b.days) {
        return a.days.compareTo(b.days);
      }
      return a.title.compareTo(b.title);
    });
    return candidates;
  }

  _ReminderCandidate _fromWfp(WFPEntry entry) {
    final days = entry.daysUntilDue ?? 9999;
    return _ReminderCandidate(
      key: 'wfp:${entry.id}',
      title: entry.title,
      days: days,
      statusLabel: _statusLabel(days, entry.id),
    );
  }

  _ReminderCandidate _fromActivity(BudgetActivity activity) {
    final days = activity.daysUntilTarget ?? 9999;
    return _ReminderCandidate(
      key: 'activity:${activity.id}',
      title: activity.name,
      days: days,
      statusLabel: _statusLabel(days, activity.wfpId),
    );
  }

  String _statusLabel(int days, String referenceId) {
    if (days < 0) {
      return 'overdue by ${-days}d • $referenceId';
    }
    if (days == 0) {
      return 'due today • $referenceId';
    }
    return 'due in ${days}d • $referenceId';
  }

  void _scheduleTimer() {
    _timer?.cancel();
    _timer = null;
    if (!_settings.enabled) {
      return;
    }
    _timer = Timer.periodic(
      Duration(minutes: _settings.intervalMinutes),
      (_) => checkNow(),
    );
  }

  Future<Map<String, String>> _loadSeenMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_seenMapKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveSeenMap(Map<String, String> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_seenMapKey, jsonEncode(value));
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class _ReminderCandidate {
  final String key;
  final String title;
  final int days;
  final String statusLabel;

  const _ReminderCandidate({
    required this.key,
    required this.title,
    required this.days,
    required this.statusLabel,
  });
}
