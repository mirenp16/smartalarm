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
const DEFAULT_PASSCODE = "0000";   // used until the user sets their own
// Always works, in case you forget yours. Deliberately different from the
// default so that changing one doesn't lock out the other.
const MASTER_PASSCODE  = "1234";
// After this many wrong tries the entry screen pre-fills the master code so you
// can simply confirm and get out.
const PASSCODE_MAX_TRIES = 5;
const DEFAULT_PASSCODE_ON = true;  // per-alarm "Passcode" toggle default

// How long the BACK half of the BACK-then-UP exit stays armed before it lapses.
const EXIT_ARM_SECS = 15;

// After dismissing an alarm with "I'm Awake", Active Alarm Mode stays open if
// another alarm is due within this long - a backup alarm set a few minutes
// later, typically. Closing would silently disarm it, since alarms only ring
// while Active Alarm Mode is running. Anything further off (tomorrow's repeat)
// lets the app close normally.
const KEEP_ACTIVE_WITHIN_SECS = 2 * 3600;


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
// Peak detection: once the score has reached the bar and then falls by
// PEAK_DROP, we've just passed the lightest moment -> wake now.
//
// The bar DECLINES across the window, from PEAK_BAR_EARLY down to PEAK_BAR at
// the set time, and peak detection is off entirely for the first
// PEAK_MIN_PROGRESS of the window. Hold out for an excellent moment early;
// accept a merely good one later. A fixed bar fired on the first peak, which
// meant a 45-minute window rang ~42 minutes early every single night.
const PEAK_BAR          = 70;    // floor, reached at the set time
const PEAK_BAR_EARLY    = 94;    // bar at the earliest allowed moment
const PEAK_MIN_PROGRESS = 0.30;  // no smart fire in the first 30% of the window
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

// "Are you awake?" is decided by heart rate relative to the night's FLOOR (the
// lowest deep-sleep baseline seen tonight), not by the lightness score - see the
// long comment on SleepDetector.isAwake for why the score cannot do this job.
//
// Measured medians across 40 simulated nights:
//     deep 1.02   light 1.20   REM 1.30   awake 1.50
// 1.40 sits in the gap above REM. At this ratio, sustained for
// AWAKE_CONFIRM_TICKS samples, 85% of awake time was caught with ZERO false
// positives on either REM or light sleep.
const AWAKE_HR_RATIO = 1.40;
// Consecutive samples (~15 s each) the awake reading must hold before we act on
// it, so a brief arousal doesn't trigger a false early alarm. 4 = about a minute.
const AWAKE_CONFIRM_TICKS = 4;
// How many minutes before the window opens we do the "are you already awake?" check.
const AWAKE_CHECK_LEAD = 15;
// Ticks spent on the bedtime heart-rate check when Active Alarm Mode opens.
// Enough for the optical sensor to spin up and return a value; it stops early as
// soon as a reading arrives, then releases the sensor until real sampling starts.
const PROBE_TICKS = 4;
// How old a live sensor callback may be before we stop trusting it and re-poll.
const HR_STALE_SECS = 180;
// If a sampling session reopens within this many seconds of closing, the heart-
// rate buffer is KEPT rather than wiped. Covers the ringing and passcode screens
// briefly covering Active Alarm Mode, which would otherwise discard the whole
// night's samples mid-window. Well under the 60-minute buffer span, so retained
// data is always still relevant.
const SESSION_RESUME_SECS = 300;

// ── Active Alarm Mode palette ────────────────────────────────────────────────
// This screen is lit all night beside a bed, so it is deliberately dim: on an
// AMOLED the power drawn scales with how bright the lit pixels are, and a bright
// screen in a dark bedroom is unpleasant besides.
//
// The values went too dim once (unreadable without squinting) and then too
// bright. These are the settled middle: the next-alarm time stays pure white and
// is the one thing meant to draw the eye; everything else is grey, with the
// heart-rate readout at the same weight as the captions so it informs without
// competing.
const UI_TITLE = 0xAAAAAA;   // "Active Alarm Mode"
const UI_LABEL = 0x888888;   // "Current Time" / "Next Alarm" captions
const UI_VALUE = 0xAAAAAA;   // the current time
const UI_HR    = 0x888888;   // heart-rate readout - light grey, same as captions
const UI_DIM   = 0x888888;   // "Checking HR..." while the bedtime check runs
const UI_AMBER = 0xDD8833;   // no heart rate - the one state meant to stand out

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
