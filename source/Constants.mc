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
const DAYS_WEEKDAYS = 0x3E;  // Mon-Fri (0b0111110)
const DAYS_ALL      = 0x7F;  // every day

// ── Repeat presets ───────────────────────────────────────────────────────────
// Shown instead of raw day lists. "Custom" opens the day checkboxes.
const DAYS_ONCE    = 0x00;   // fires once, then switches itself off
const DAYS_4X10    = 0x1E;   // Mon-Thu  (bits 1-4)
const DAYS_WEEKEND = 0x41;   // Sat + Sun (bits 6 and 0)
const REPEAT_CUSTOM = -1;    // sentinel: open the day picker

// ── Alarm type ───────────────────────────────────────────────────────────────
const TYPE_SLEEP    = 0;  // uses the Wake Window + smart light-sleep detection
const TYPE_REMINDER = 1;  // fires exactly at the set time, no sleep checking

// ── Alert mode ───────────────────────────────────────────────────────────────
const MODE_BOTH  = 0;  // vibration + sound
const MODE_SOUND = 1;  // sound only
const MODE_VIBE  = 2;  // vibration only
const DEFAULT_ALERT_MODE = MODE_VIBE;
const DEFAULT_RINGTONE   = 0;   // index into Ringtone.names() (first available tone)

// ── Passcode ─────────────────────────────────────────────────────────────────
// Plain text on purpose: this is friction to make you wake up, not security.
const DEFAULT_PASSCODE = "9999";   // used until the user sets their own
// Always works, in case you forget yours. Deliberately NOT 0000, because 0000 is
// what the entry screen already shows - that would be too easy to type by reflex.
const MASTER_PASSCODE  = "1234";
// After this many wrong tries the entry screen pre-fills the master code so you
// can simply confirm and get out.
const PASSCODE_MAX_TRIES = 5;
const DEFAULT_PASSCODE_ON = true;  // per-alarm "Passcode" toggle default

// How long the BACK half of the BACK-then-UP exit stays armed before it lapses.
const EXIT_ARM_SECS = 15;

// ── Sleep Cycle Window options (minutes before the set time) ─────────────────
// 15 min was dropped: simulation showed it barely beats a plain alarm (0.53 vs
// 0.47 lightness) because there isn't enough of a sleep cycle to find a light
// moment in. 45 min is the default - it's the knee of the curve, where extra
// window stops buying much (45->60 gains only +0.02 for 12 more minutes in bed).
const WINDOW_OPTIONS = [30, 45, 60, 75];
const DEFAULT_WINDOW = 45;

// ── Sleep detection tuning ───────────────────────────────────────────────────
// Scores are RELATIVE to your own night (see SleepDetector.mc), so these are
// stable across people. Values chosen by simulating 100 nights.
//
// Peak detection: once the score has reached PEAK_BAR and then falls by
// PEAK_DROP, we've just passed the lightest moment -> wake now.
const PEAK_BAR  = 70;
const PEAK_DROP = 8;
// In the last stretch of the window, accept any reasonably light moment.
const LATE_FRACTION = 0.90;
const LATE_BAR      = 50;

// Heart-rate buffer (sampled every ~15 s while Active Alarm Mode runs).
const MAX_HR_SAMPLES = 240;   // ~60 minutes of history
const MIN_HR_SAMPLES = 40;    // ~10 minutes before we trust the score
const RECENT_SAMPLES = 12;    // ~3 minutes counts as "recent"
// Re-sort the buffer for percentiles only every N new samples (~1 min), instead
// of every tick. Sorting every tick allocated a new array 4x a minute all night.
const RECALC_EVERY   = 4;

// If lightness is at/above this BEFORE the window even opens, we treat the user
// as already awake and just fire at the set time.
const AWAKE_THRESHOLD = 88;
// How many minutes before the window opens we do the "are you already awake?" check.
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
const DEFAULT_MAX_SNOOZE      = 3;
const SNOOZE_LEN_OPTIONS = [1, 3, 5, 10, 15];
// 0 = no snoozing at all (the alarm can only be turned off by waking up).
const SNOOZE_MAX_OPTIONS = [0, 1, 2, 3, 4, 5, 10];

// ── Limits ───────────────────────────────────────────────────────────────────
const MAX_ALARMS = 20;   // most saved alarms allowed

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
const KEY_PASSCODE     = "passcode";    // global 4-digit code (plain text)
