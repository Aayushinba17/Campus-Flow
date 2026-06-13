class AppConstants {
  // ── Replace with your EC2 public IP ──────────────────────────────────
  static const String baseUrl = 'http://13.234.29.16';

  // ── For demo/testing without EC2 ─────────────────────────────────────
  // static const String baseUrl = 'http://10.0.2.2:8000'; // Android emulator localhost

  // ── User ID (in production: use Firebase Auth or similar) ─────────────
  // For hackathon: hardcode a user ID for demo
  static const String userId = 'demo_user_001';

  // ── API Endpoints ─────────────────────────────────────────────────────
  static const String scheduleUpload     = '/api/schedule/upload-image';
  static const String scheduleClasses    = '/api/schedule/classes';
  static const String scheduleToday      = '/api/schedule/today';
  static const String scheduleEvent      = '/api/schedule/event';
  static const String scheduleChecklist  = '/api/schedule/exam-checklist';

  static const String notifIngest        = '/api/notifications/ingest';
  static const String notifDigest        = '/api/notifications/digest';
  static const String notifRecent        = '/api/notifications/recent';
  static const String notifDeadlines     = '/api/notifications/deadlines';
  static const String notifMarkRead      = '/api/notifications/mark-read';

  static const String routineUsageLog    = '/api/routine/usage-log';
  static const String routineHeatmap     = '/api/routine/heatmap';
  static const String routineContext     = '/api/routine/activity-context';
  static const String routineSleepLog    = '/api/routine/sleep-log';
  static const String routineSleepSumm   = '/api/routine/sleep-summary';
  static const String routineInsights    = '/api/routine/generate-insights';
  static const String routineBattery     = '/api/routine/battery-log';

  static const String remindersPreClass  = '/api/reminders/pre-class';
  static const String remindersWellness  = '/api/reminders/wellness-check';
  static const String remindersDismiss   = '/api/reminders/dismiss-wellness';
  static const String remindersStress    = '/api/reminders/stress-density';
  static const String tasksBase          = '/api/reminders/tasks';

  static const String chatMessage        = '/api/chat/message';
  static const String chatVoice          = '/api/chat/voice-to-tasks';
  static const String chatHistory        = '/api/chat/history';

  static const String notesProcess       = '/api/notes/process-text';
  static const String notesList          = '/api/notes/list';
  static const String notesAsk           = '/api/notes/ask';

  static const String wellnessPomodoro   = '/api/wellness/pomodoro';
  static const String wellnessSummary    = '/api/wellness/weekly-summary';
  static const String wellnessSleep      = '/api/wellness/sleep-reminder';

  // ── App Config ────────────────────────────────────────────────────────
  static const int notifBatchSize        = 50;
  static const int notifSyncIntervalMins = 30;
  static const int digestHour            = 8;   // 8 AM
  static const int waterReminderMins     = 90;
  static const int preClassReminderMins  = 30;

  // ── WorkManager Task Names ────────────────────────────────────────────
  static const String taskDigest         = 'morning_digest';
  static const String taskNotifSync      = 'notification_sync';
  static const String taskUsageSync      = 'usage_stats_sync';
  static const String taskWellness       = 'wellness_reminders';
  static const String taskSleepCheck     = 'sleep_check';
}