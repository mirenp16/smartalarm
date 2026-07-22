// Constants.mc
// Shared, compile-time constants used across the whole app (foreground AND
// background). These are plain top-level consts so they're available everywhere
// without needing a (:background) annotation.

// ── Day-of-week bitmask ──────────────────────────────────────────────────────
// One bit per day. bit 0 = Sunday ... bit 6 = Saturday.
// Matches Garmin's Gregorian day_of_week (1=Sun..7=Sat) shifted to 0-indexed.
const DAY_SUN = 0x01;  // 0b0000001
const DAY_MON = 0x02;  // 0b0000010
const DAY_TUE = 0x04;  // 0b0000100
const DAY_WED = 0x08;  // 0b0001000
const DAY_THU = 0x10;  // 0b0010000
const DAY_FRI = 0x20;  // 0b0100000
const DAY_SAT = 0x40;  // 0b1000000
const DAYS_WEEKDAYS = 0x3E;  // Mon–Fri (0b0111110)
const DAYS_ALL      = 0x7F;  // every day

// ── Alarm type ───────────────────────────────────────────────────────────────
const TYPE_SLEEP    = 0;  // uses the Wake Window + smart light-sleep detection
const TYPE_REMINDER = 1;  // fires exactly at the set time, no sleep checking

// ── Alert mode ───────────────────────────────────────────────────────────────
const MODE_BOTH  = 0;  // vibration + sound
const MODE_SOUND = 1;  // sound only
const MODE_VIBE  = 2;  // vibration only

// ── Wake Window options (minutes before the set time) ────────────────────────
const WINDOW_OPTIONS = [15, 30, 45, 60];

// ── Sleep detection tuning ───────────────────────────────────────────────────
// Lightness score (0=deep, 100=very light). Fire when we cross this.
const LIGHT_SLEEP_THRESHOLD = 65;
// If lightness is at/above this BEFORE the window even opens, we treat the user
// as already awake and downgrade a Sleep alarm to a plain fire-on-time alarm.
const AWAKE_THRESHOLD = 80;
// How many minutes before the window opens we do the "are you already awake?"
// check. Spec: 15 minutes before the window starts.
const AWAKE_CHECK_LEAD = 15;

// ── Background timing ────────────────────────────────────────────────────────
// Garmin's minimum temporal-event interval is 5 minutes (300 s). We re-register
// at this cadence so the service keeps polling.
const CHECK_INTERVAL_SECS = 300;
// How long after the set time an alarm may still fire. Past this we treat it as
// "missed" (so enabling a 7:00 alarm at 11pm doesn't ring instantly). Wider than
// the 5-min sampling so we never skip a legitimate fire.
const FIRE_GRACE_MINS = 15;

// ── Snooze defaults ──────────────────────────────────────────────────────────
const DEFAULT_SNOOZE_MINUTES = 5;
const DEFAULT_MAX_SNOOZE      = 5;

// ── Storage keys ─────────────────────────────────────────────────────────────
// Kept here so foreground and background always agree on the exact strings.
const KEY_ALARMS       = "alarms";      // Array of alarm Dictionaries
const KEY_NEXT_ID      = "nextId";      // running counter for unique alarm ids
const KEY_STATE_DAY    = "stateDay";    // day-of-year the daily state belongs to
const KEY_DAY_STATE    = "dayState";    // Dictionary: idStr -> per-day flags
const KEY_RING_ID      = "ringId";      // id of the alarm currently ringing, or null
const KEY_RING_START   = "ringStart";   // moment (epoch secs) ringing began
const KEY_SNOOZE_UNTIL = "snoozeUntil"; // epoch secs to re-fire a snoozed alarm
const KEY_SNOOZE_ID    = "snoozeAlarmId"; // which alarm id is snoozed
const KEY_SNOOZE_MINS  = "snoozeMins";  // configurable snooze length
const KEY_MAX_SNOOZE   = "maxSnooze";   // configurable max snooze count
