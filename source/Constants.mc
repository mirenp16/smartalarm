// Constants.mc
// Shared, compile-time constants used across the whole app. Tuning values are
// grouped here so behaviour can be adjusted without touching program logic.

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
// ── Repeat presets ───────────────────────────────────────────────────────────
// Built from the day bits above so the mapping is self-evident.
// "Custom" opens the day checkboxes instead of using a preset.
const DAYS_ONCE     = 0x00;                                        // fires once, then off
const DAYS_4X10     = DAY_MON | DAY_TUE | DAY_WED | DAY_THU;       // 0x1E
const DAYS_WEEKDAYS = DAY_MON | DAY_TUE | DAY_WED | DAY_THU | DAY_FRI;  // 0x3E
const DAYS_WEEKEND  = DAY_SAT | DAY_SUN;                           // 0x41
const DAYS_ALL      = 0x7F;                                        // every day
const REPEAT_CUSTOM = -1;    // sentinel: open the day picker

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

// Time picker: holding UP/DOWN moves the MINUTES in larger steps, so setting
// :45 doesn't take 45 presses. Hours and AM/PM always move one step per press.
const HOLD_MS           = 450;   // press longer than this counts as a hold
const MINUTE_STEP_HOLD  = 5;     // minutes per held press

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
// Heart-rate range used for the counting-sort percentile calculation.
const HR_MIN   = 25;
const HR_RANGE = 176;   // covers 25-200 bpm
// Longest Sleep Cycle Window offered, plus how long before it we start reading
// the heart-rate sensor. Outside that span the app just watches the clock, which
// is most of the night - this is the single biggest battery saving.
const MAX_WINDOW_MINS  = 75;
// Must cover AWAKE_CHECK_LEAD (15) plus the detector's ~10 min warm-up, or the
// "are you already awake?" check runs before enough samples exist and can never
// trigger. 30 leaves a safe margin.
const SAMPLE_LEAD_MINS = 30;

// Timer cadence. We only need 15 s precision near the alarm; the rest of the
// night a 60 s tick is plenty and wakes the CPU 4x less often.
const TICK_FAST_MS = 15000;
const TICK_SLOW_MS = 60000;
// Switch to the fast tick when the next alarm is within this many seconds.
const FAST_TICK_WITHIN_SECS = (MAX_WINDOW_MINS + SAMPLE_LEAD_MINS) * 60;

// If lightness is at/above this BEFORE the window even opens, we treat the user
// as already awake and just fire at the set time.
const AWAKE_THRESHOLD = 88;
// How many minutes before the window opens we do the "are you already awake?" check.
const AWAKE_CHECK_LEAD = 15;

// ── Firing tolerance ─────────────────────────────────────────────────────────
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
const KEY_PASSCODE     = "passcode";    // global 4-digit code (plain text)
