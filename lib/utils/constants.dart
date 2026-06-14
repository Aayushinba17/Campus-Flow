class AppConstants {
  // ── Replace with your EC2 public IP ──────────────────────────────────
  static const String baseUrl = 'http://3.80.224.136:8001';

  // ── For demo/testing without EC2 ─────────────────────────────────────
  // static const String baseUrl = 'http://10.0.2.2:8000'; // Android emulator localhost

  // ── User ID (in production: use Firebase Auth or similar) ─────────────
  static const String userId = 'demo_user_001';

  // ── API Endpoints ─────────────────────────────────────────────────────

  // Schedule
  static const String scheduleUpload     = '/api/schedule/upload-image';
  static const String scheduleClasses    = '/api/schedule/classes';
  static const String scheduleToday      = '/api/schedule/today';
  static const String scheduleEvent      = '/api/schedule/event';
  static const String scheduleFreeSlots  = '/api/schedule/free-slot-suggestions';
  static const String scheduleBookings   = '/api/schedule/detect-bookings';
  static const String scheduleConfirmBk  = '/api/schedule/confirm-booking';
  static const String scheduleDismissBk  = '/api/schedule/dismiss-booking';
  static const String scheduleExamCount  = '/api/schedule/exam-countdown';
  static const String scheduleChecklist  = '/api/schedule/exam-checklist';
  static const String notesSemanticSearch = '/api/notes/semantic-search';
  static const String notesReembed        = '/api/notes/reembed';

  // Notifications
  static const String notifIngest        = '/api/notifications/ingest';
  static const String notifDigest        = '/api/notifications/digest';
  static const String notifRecent        = '/api/notifications/recent';
  static const String notifDeadlines     = '/api/notifications/deadlines';
  static const String notifMarkRead      = '/api/notifications/mark-read';
  static const String notifMissedCall    = '/api/notifications/missed-call-context';
  static const String notifMissedCalls   = '/api/notifications/missed-calls';
  static const String notifExtractDead   = '/api/notifications/extract-deadlines';
  static const String notifStats         = '/api/notifications/stats';

  // Routine
  static const String routineUsageLog    = '/api/routine/usage-log';
  static const String routineHeatmap     = '/api/routine/heatmap';
  static const String routineContext     = '/api/routine/activity-context';
  static const String routineCurrCtx     = '/api/routine/current-context';
  static const String routineSleepLog    = '/api/routine/sleep-log';
  static const String routineSleepSumm   = '/api/routine/sleep-summary';
  static const String routineInsights    = '/api/routine/generate-insights';
  static const String routineBattery     = '/api/routine/battery-log';

  // Reminders
  static const String remindersPreClass  = '/api/reminders/pre-class';
  static const String remindersSmartBtch = '/api/reminders/smart-batch';
  static const String remindersBooking   = '/api/reminders/booking-reminder';
  static const String remindersWellness  = '/api/reminders/wellness-check';
  static const String remindersDismiss   = '/api/reminders/dismiss-wellness';
  static const String remindersStress    = '/api/reminders/stress-density';
  static const String tasksBase          = '/api/reminders/tasks';

  // Chat & AI
  static const String chatMessage        = '/api/chat/message';
  static const String chatVoice          = '/api/chat/voice-to-tasks';
  static const String chatHistory        = '/api/chat/history';
  static const String chatClear          = '/api/chat/history';
  static const String chatSearch         = '/api/chat/search-messages';
  static const String chatStudyAvail     = '/api/chat/study-availability';

  // Notes
  static const String notesProcess       = '/api/notes/process-text';
  static const String notesList          = '/api/notes/list';
  static const String notesAsk           = '/api/notes/ask';
  static const String notesDelete        = '/api/notes';
  static const String notesSemanticSearch = '/api/notes/semantic-search';

  // Wellness
  static const String wellnessPomodoro   = '/api/wellness/pomodoro';
  static const String wellnessSummary    = '/api/wellness/weekly-summary';
  static const String wellnessSleep      = '/api/wellness/sleep-reminder';

  // Email Summarization
  static const String emailSummarize     = '/api/emails/summarize';
  static const String emailFromNotifs    = '/api/emails/summarize-from-notifications';
  static const String emailActionItems   = '/api/emails/action-items';

  // Location Context
  static const String locationOnboard    = '/api/location/onboard-zones';
  static const String locationTransition = '/api/location/zone-transition';
  static const String locationCurrent    = '/api/location/current-zone';
  static const String locationDetect     = '/api/location/detect-zone';
  static const String locationAdjusted   = '/api/location/adjusted-reminder-time';
  static const String locationZones      = '/api/location/zones';
  static const String locationHistory    = '/api/location/history';

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

  // Google Classroom
static const String classroomOAuthStart = '/api/classroom/oauth/start';
static const String classroomStatus     = '/api/classroom/status';
static const String classroomSync       = '/api/classroom/sync';
static const String classroomSyncAnn    = '/api/classroom/sync-announcements';
static const String classroomDisconnect = '/api/classroom/disconnect';

// New WorkManager task
static const String taskClassroomSync   = 'classroom_sync';
}