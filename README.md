# Smart Alarm — Sleep-Cycle Alarm for Garmin

A Connect IQ watch app for the Garmin Forerunner 265S that wakes you during **light sleep**
instead of at a fixed time, using live heart-rate analysis. It adds a configurable snooze
system and a passcode gate designed to make it genuinely hard to fall back asleep.

Written in **Monkey C** against the **Connect IQ SDK 9.x**.

---

## How it works in one minute

A normal alarm fires at a fixed time, often yanking you out of deep sleep. This one watches a
**Sleep Cycle Window** before your set time and rings at the lightest moment it finds.

```
    05:15 ─────────────── 06:00        Alarm set for 06:00
    └── Sleep Cycle Window ──┘         with a 45-minute window

    Heart rate is sampled every 15 s.
    It rings at the lightest point inside the window — say 05:38 —
    or at 06:00 regardless, so you are never late.
```

**Three things to know before using it:**

1. **Alarms only ring while "Active Alarm Mode" is open.** You start it at bedtime from the
   main screen. This is a Garmin platform limitation, not a bug — background apps are not
   permitted to vibrate or make sound ([details below](#why-active-alarm-mode-exists)).
2. **Vibrate Only is the default**, because the watch mutes app tones when its Alert Tones
   setting is off — a different setting from the built-in alarm's.
3. **A passcode is required to switch the alarm off**, which is the point: typing four digits
   is what proves you're actually awake.

---

## Engineering highlights

Most of the interesting work here came from designing *around* platform limits rather than
within them:

- **Built sleep staging from scratch.** Garmin does not expose sleep stages to third-party
  apps, so light sleep is inferred from heart-rate percentiles computed against each
  individual night — no absolute thresholds, so it generalises across people and nights.
- **Wake timing by peak detection, not a cut-off.** The alarm fires just *after* the
  lightness score crests, which detects that the lightest moment has passed rather than
  guessing when it will arrive.
- **Framed wake timing as optimal stopping.** A fixed quality bar fired on the first peak, so
  a 45-minute window rang 42 minutes early every night. A bar that declines toward the
  deadline recovers half the window at no cost to wake quality.
- **Tuned by simulation, not intuition.** 80 synthetic nights per configuration with
  randomised sleep-cycle phase, calibrated to real exported sleep data.
- **Found a silent data-starvation bug by algebra.** Proving a threshold was unreachable given
  the scoring formula's ceiling turned "the feature feels unreliable" into a specific defect.
- **Diagnosed a fatal memory leak** from allocation counting: 1,920 font allocations per
  night reduced to 1.
- **Cut overnight workload 60–72%** with adaptive sensor sampling and a variable tick rate,
  without losing wake-time precision.
- **Turned silent failures into diagnosable ones** — a swallowed exception in the audio path
  was hiding a device setting, so capability probing and error reporting were added.

## Contents

- [How it works in one minute](#how-it-works-in-one-minute)
- [What it does](#what-it-does)
- [Why Active Alarm Mode exists](#why-active-alarm-mode-exists)
- [Sleep-cycle detection](#sleep-cycle-detection)
- [Algorithm validation](#algorithm-validation)
- [Post-mortem: why smart wake never fired](#post-mortem-why-smart-wake-never-fired)
- [How the algorithm is verified](#how-the-algorithm-is-verified)
- [Passcode system](#passcode-system)
- [Snooze model](#snooze-model)
- [Battery engineering](#battery-engineering)
- [Architecture](#architecture)
- [Data model](#data-model)
- [Platform constraints discovered](#platform-constraints-discovered)
- [Testing](#testing)
- [Build and install](#build-and-install)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [Known limitations](#known-limitations)
- [License](#license)

---

## What it does

A conventional alarm fires at a fixed time, which frequently drags you out of deep sleep —
the cause of grogginess (sleep inertia). This app instead watches a **Sleep Cycle Window**
before your set time and fires at the lightest moment it can find inside it.

| Feature | Detail |
|---|---|
| Smart wake | Fires during light sleep within a 30/45/60/75-minute window |
| Deadline guarantee | Always fires by your set time if no light moment is found |
| Already-awake detection | Rings immediately if you wake up on your own inside the window |
| Repeat presets | Once, Daily, 4x10 (Mon–Thu), Weekdays, Weekend, Custom |
| Per-alarm config | Label, window, alert mode, ringtone, snooze length, max snoozes, passcode |
| Passcode gate | 4-digit code required to dismiss, with master-code recovery |
| Alarm capacity | Up to 20 saved alarms |

---

## Why Active Alarm Mode exists

This is the central architectural decision, and it's driven by a hard platform constraint.

Connect IQ background services **cannot vibrate, play tones, or bring an app to the
foreground**. The only mechanism available is `Background.requestApplicationWake()`, which
shows a system confirmation prompt and waits for the user to notice it. Background services
also run at most **once every 5 minutes**, for at most 30 seconds.

On-device testing matched those constraints exactly: an alarm set for 08:35 stayed silent at
08:35 and only triggered when the wrist was raised some minutes later — and even then it
surfaced an "Open Smart Alarm?" confirmation prompt rather than actually ringing.

**Active Alarm Mode** is the workaround. It is a foreground view you enter at bedtime. Because
the app holds the foreground, it can:

- run its own timer at 15-second resolution rather than 5-minute polling
- vibrate and play tones directly, with no system prompt
- present the ringing screen immediately

The trade-off is explicit: **alarms only fire while Active Alarm Mode is running.** Rather
than failing silently, the app surfaces this — "Alarm Activation Mode" is the first entry on
the main screen, directly beneath the count of enabled alarms.

---

## Sleep-cycle detection

Garmin does **not** expose real-time sleep stages to third-party apps. Sleep staging must
therefore be derived from raw signals available to a foreground app.

### Signal

Heart rate is sampled every 15 seconds into a fixed 240-sample ring buffer (~60 minutes).
Accelerometer data proved unusable — `Sensor.getInfo().accel` returns null without an active
sensor registration, so movement is not part of the score.

### Scoring

The key design decision is that **all thresholds are relative to your own night**, not
absolute BPM values. Absolute thresholds fail across individuals and across nights.

```
base  = 20th percentile of buffer     // your deep-sleep floor
top   = 85th percentile of buffer     // your light/REM ceiling
span  = max(top - base, 2.0)          // guard against a flat night

elevation   = clamp((mean(recent 12 samples) - base) / span, 0, 1)
variability = clamp(meanAbsDiff(recent) / (2 * meanAbsDiff(all)), 0, 1)

lightness   = 100 * (0.60 * elevation + 0.40 * variability)
```

Physiologically: during deep sleep, heart rate is low and very steady. In light/REM sleep it
rises and becomes more variable. `elevation` captures the rise, `variability` captures the
irregularity, weighted 60/40 toward the more reliable signal.

Garmin's stress metric (HRV-derived) is blended in at 15% weight when the device exposes it,
but **only where it raises the score**, never lowers it. As a plain weighted average it was
actively harmful: stress is low while you sleep — that is what sleeping is — so the average
dragged every score down and imposed a hard ceiling of `85 + 0.15 × stress`. At a typical
sleeping stress of 15 the highest attainable score was 87, which made the awake threshold of
88 *mathematically unreachable*.

In simulation this separates deep from light sleep cleanly, but **not light sleep from
being awake** — a limitation that matters, and is handled separately below:

| True state | Mean score |
|---|---|
| Deep | 16 |
| Light | 84 |
| Awake | 90 |

### Wake decision

The detector uses **peak detection against a declining bar** — it fires just *after* the
score crests, meaning you've passed the lightest point. The bar falls as the deadline
approaches, so early in the window only an excellent moment qualifies:

```
bar(progress) = 70 + 24 * (1 - progress)        # 94 at the start, 70 at the set time

if awake for 4 consecutive samples:                             fire
if progress >= 30% and best >= bar and current <= best - 8:     fire
if progress >= 90% of window and current >= 50:                 fire
if now >= set time:                                             fire (hard deadline)
```

The declining bar is the difference between a smart alarm and a merely early one. With a
fixed bar the very first peak almost always qualified, so a 45-minute window rang ~42
minutes early *every night* — technically light sleep, but it threw away most of the window.
Framing it as an optimal-stopping problem (hold out early, grow less fussy later) recovers
about half the window at no cost to wake quality.

A 10-minute warm-up (`MIN_HR_SAMPLES = 40`) is required before the score is trusted; until
then the detector reports "insufficient data" and the deadline governs.

### Detecting "awake" needs a different signal

The lightness score is normalised against a rolling 60-minute buffer, so during a long light
stretch the recent mean sits at the top of its own distribution and scores ~84 — statistically
indistinguishable from genuinely awake (~90). No threshold on that score separates them.

Awake detection therefore compares recent heart rate against the **night floor**: the lowest
deep-sleep baseline seen since sampling began, a long-horizon reference. That separates the
states cleanly (measured medians):

| State | HR / night floor |
|---|---|
| Deep | 1.02 |
| Light | 1.20 |
| REM | 1.30 |
| **Awake** | **1.50** |

A ratio of **1.40 held for 4 consecutive samples (~1 min)** caught 85% of awake time with
**zero** false positives on REM or light sleep. The persistence requirement is what rejects
brief arousals, which are a normal part of sleep and must not trigger the alarm.

---

## Algorithm validation

The detector was validated against **synthetic nights** modelling 80–105 minute sleep cycles
with randomised phase, cycle length and noise, calibrated to real exported Garmin sleep data
(6.65 h mean duration, ~4.4 cycles/night).

Wake quality is measured as sleep "lightness" at the moment of firing, where **0.45 is the
baseline** for a fixed-time alarm and 1.0 is the theoretical optimum.

| Window | Woke early | Avg minutes early | Lightness at wake |
|---|---|---|---|
| 30 min | 85% | 15 | 0.63 |
| **45 min** | **100%** | **21** | **0.66** |
| 60 min | 100% | 30 | 0.61 |
| 75 min | 100% | 43 | 0.53 |

**45 minutes is the default.** It is the shortest window that wakes you early every night,
and it spends less than half the time it is allowed. The 15-minute option was removed — there
isn't enough of a sleep cycle inside it to beat a fixed alarm.

### Cross-validation on a second model

Tuning and validating on the same synthetic model would prove very little, so the algorithm
was re-run against an independently written one: variable 80–105 minute cycles, per-stage
drift, random micro-arousals, a slow whole-night decline in heart rate, and a different
random seed stream. Nothing is shared with the first model but the detector itself.

| Window | Woke early | Avg minutes early | Lightness gain over a fixed alarm |
|---|---|---|---|
| 30 min | 85% | 12.5 | +0.13 |
| 45 min | 100% | 21.6 | +0.14 |
| 60 min | 100% | 32.0 | +0.14 |
| 75 min | 100% | 42.3 | +0.17 |

Zero timing violations: it never fired late, and never before the window opened. The
improvement over a fixed alarm holds on both models. Which window ranks *best* does not —
the first model favours 45 minutes, the second mildly favours longer ones — so treat the
window as a personal preference, not a solved optimum. What is robust across both is that
every window beats a fixed-time alarm, and that 45 minutes is a sound default.

> An earlier version of this algorithm never fired early once. Analysis showed its score was
> computed against a fixed scale and **peaked at 43 against a threshold of 65** — it was
> mathematically incapable of triggering. This is why the current version is scored relative
> to the night's own distribution and validated numerically rather than by inspection.

---

## Passcode system

The passcode is deliberately **plain text**. Its purpose is friction to force wakefulness, not
security; encrypting it would add complexity for no threat model.

- **Global 4-digit code**, shared by all alarms (`Passcode Setup` on the main screen)
- **Default `9999`** until the user sets one
- **Master code `1234`** always works as recovery. Deliberately not `0000`, since `0000` is
  the entry screen's initial state and would be typed by reflex
- **After 5 wrong attempts** the master code is pre-filled and displayed, so a half-asleep
  user is never locked out
- **Per-alarm toggle** — an alarm with `Passcode: No` dismisses with the button combo alone

Entry uses the same one-digit-at-a-time mechanism as the time picker (UP/DOWN to change,
START to advance). BACK cannot escape the entry screen — that would defeat the purpose.

### Gating rules

A passcode is required to **dismiss a ringing alarm** and to **exit Active Alarm Mode**. The
governing alarm is resolved in priority order:

1. a currently snoozed alarm
2. a currently ringing alarm
3. the next upcoming alarm

Resolving snoozed alarms first closes a real bypass: snoozing a one-time alarm disables it,
which previously made the "next alarm" lookup return nothing and allowed a code-free exit.

---

## Snooze model

Snooze length (1/3/5/10/15 min) and maximum count (0–10) are **per-alarm**. Setting max to 0
disables snoozing entirely.

Both the ringing screen and the Active Alarm Mode exit use a deliberate **two-step button
combo — BACK then UP** — with strict sequence enforcement: any other button press resets it.
This was verified exhaustively across all 1,296 four-key permutations, and 100,000 randomised
non-BACK/UP press sequences produced zero accidental dismissals.

Alarm controls stay **hidden until a button is pressed**, so the alarm simply rings rather
than presenting a dismissable UI to a half-asleep user.

---

## Battery engineering

Running a foreground app all night is inherently costly. Two optimisations reduce the work
per night by **60–72%**:

**Adaptive sampling.** The heart-rate sensor is only read within `MAX_WINDOW_MINS +
SAMPLE_LEAD_MINS` (105 min) of the next alarm. For most of the night the app only compares
the clock — leaving the sensor idle ~80% of an 8-hour night.

**Adaptive tick rate.** The timer runs at 60 s when hours from an alarm and 15 s as it
approaches, cutting CPU wakeups 4× without affecting wake precision.

| Sleep | Wakeups + sensor reads (before) | After | Saving |
|---|---|---|---|
| 6h | 1,440 + 1,440 | 645 + 380 | 64% |
| 8h | 1,920 + 1,920 | 765 + 380 | 70% |

### Memory: a crash post-mortem

An early build crashed overnight with the Connect IQ `IQ!` error, taking the alarm with it.
Root cause: `Graphics.getVectorFont()` was called on **every redraw** — ~1,920 font
allocations per night — alongside a 240-element array sorted every tick and a bitmap reloaded
each draw. Connect IQ's memory ceiling made this fatal.

Fixes: cache fonts and bitmaps, recompute percentiles 4× less often, redraw once per minute
instead of every 15 s, and wrap the entire overnight tick in `try/catch` so a transient
sensor or scheduling exception can never kill the alarm.

| Metric (8h night) | Before | After |
|---|---|---|
| Font allocations | 1,920 | **1** |
| Bitmap loads | 1,920 | **1** |
| Buffer sorts | 1,881 | 51 |
| Redraws | 1,920 | 480 |

### Execution time: the instruction watchdog

The crash recurred after the memory fixes, which ruled memory out. Connect IQ enforces a
second, independent limit: a **watchdog that counts VM instructions** and terminates the app
if a callback runs too long. Profiling the overnight tick found two causes.

**Redundant expensive calls.** Each tick performed ~87 persistent-storage deserialisations of
the alarm array and ~63 `Gregorian.info()` calendar conversions, because `nextFireEpoch()`
called `Gregorian.info()` once *per alarm*, and the alarm scan itself ran three separate
times per tick. Fixed with an in-memory alarm cache invalidated on write, a day-context cache
recomputed at most once a minute, and computing the next-alarm distance once per tick and
reusing it.

**An O(n²) sort in a callback.** Percentiles were computed with an insertion sort over the
240-sample buffer — roughly 14,000 operations inside a timer callback. Replaced with a
**counting sort** over the 25–200 bpm range: O(n + range), ~416 operations, allocating
nothing.

| Per tick / recompute | Before | After |
|---|---|---|
| Storage reads | ~87 | ~1 |
| `Gregorian.info()` calls | ~63 | ~1 |
| Percentile operations | ~14,400 | ~416 |

The substitution was validated for behavioural equivalence across 300 simulated nights:
identical wake moment on 267, and mean wake quality unchanged (0.715 → 0.722).

---

## Post-mortem: why smart wake never fired

For a long stretch the app behaved exactly like an ordinary alarm — it always rang at the set
time, never earlier. There was no crash and no error. **Three independent bugs** were each
sufficient on their own to cause it, and all three failed silently.

**1. No heart-rate data at all.** The only source was
`Activity.getActivityInfo().currentHeartRate`, which is populated by an *activity session* and
returns null outside one. Every sample returned null, the buffer stayed empty, the score
returned "insufficient data" forever, and every alarm fell through to the deadline. It had
appeared to work briefly while an `ActivityRecording` session was open — that session was what
powered the field, and removing the recording for battery reasons silently removed the data
source with it. The fix opens a real `Sensor` session and reads from four sources in order:
live sensor callback, direct sensor poll, activity info, then sensor history.

**2. A frozen baseline.** The staleness checks were written as `samples.size() - lastCalc >=
RECALC_EVERY`. The buffer is a ring capped at 240 samples, so `size()` stops changing once it
fills — roughly 60 minutes into sampling, which is exactly when the wake window opens. From
that moment the percentile baseline and the lightness score never updated again. Everything
that asks "has new data arrived?" now keys off a monotonic counter instead.

**3. An unreachable threshold.** The stress blend capped the score at 87 while the awake
threshold was 88 (see [Scoring](#scoring)).

Two further defects of the same kind were found later, both living in the *seams* between
components rather than inside any one of them — which is why unit tests on the detector alone
could never have caught them:

**4. One alarm erased another's state.** The detector is a singleton holding one window's peak
state, but the scheduling loop visits every enabled alarm, and each alarm not currently in a
window called `resetWindow()`. With a weekday and a weekend alarm both switched on, the
far-off one wiped the peak on every tick, so "the score has fallen below its peak" could never
become true. Average wake lead collapsed from **21.4 minutes with one alarm to 4.4 with two**.
The reset is now deferred until the whole list has been examined.

**6. Dismissing one alarm disarmed the next.** `finishAwake()` guarded the exit on
`validSnoozeId() == null` — but the line immediately above it cleared the snooze, so the
guard was always true and Active Alarm Mode closed unconditionally. Since alarms only ring
while that screen is open, dismissing a 06:00 alarm silently disarmed a 06:30 backup: exactly
the failure a backup alarm exists to prevent. The app now stays open when another alarm is
due within `KEEP_ACTIVE_WITHIN_SECS`.

**5. Covering the screen threw away the night's data.** `onHide()` releases the sensor — but it
fires whenever the view is merely *covered*, including by the passcode screen. Opening the
passcode at 06:30 inside a 06:15–07:00 window and then cancelling discarded every sample and
needed another ten minutes of warm-up. The buffer is now retained across gaps shorter than
`SESSION_RESUME_SECS`, since heart rate from three minutes ago is still good evidence.

The lasting fix is not any of the three patches but the **HR readout on the Active Alarm
screen**. All three bugs were invisible from the watch: a dead sensor and a healthy one
produced identical behaviour. One dim line showing live BPM, sample count and the active
source makes the difference obvious at a glance.

---

## Architecture

21 Monkey C source files, separated into data, logic, and presentation layers.

```
source/
├── SmartAlarmApp.mc      Application entry point and view routing
│
│   ── Data layer ──
├── AlarmStore.mc         Persistence, CRUD, per-day runtime state, passcode
├── Constants.mc          All tuning values and storage keys
│
│   ── Logic layer ──
├── AlarmEngine.mc        Scheduling: what fires, when, and what governs the exit
├── SleepDetector.mc      Heart-rate buffer, lightness scoring, peak detection
├── Ringtone.mc           Device tone enumeration with runtime capability checks
│
│   ── Presentation ──
├── MainListMenu.mc       Home screen (CustomMenu with toggle + status icons)
├── AlarmDetailMenu.mc    Per-alarm settings
├── BedsideView.mc        Active Alarm Mode
├── RingingView.mc        Ringing screen, snooze/dismiss
├── PasscodeView.mc       4-digit entry and setup
├── TimePicker.mc         Hour/minute/AM-PM picker
├── RepeatMenu.mc         Repeat presets
├── Pickers.mc            Custom day checkboxes
├── ChoiceView.mc         Reusable single-choice screen with wrapped descriptions
├── RingtoneMenu.mc       Ringtone selection with live preview
├── OptionMenu.mc         Generic option list
├── MessageView.mc        Popup with explicit line-break support
├── Icons.mc              Status glyphs and the ON/OFF pill switch
├── Ui.mc                 Curved bezel button labels with vertical fallback
└── Format.mc             Time and repeat formatting
```

### Notable implementation details

**Curved bezel labels.** Button hints are drawn as coloured arcs at the physical button
positions (START 2 o'clock, BACK 4 o'clock, UP 9 o'clock, DOWN 8 o'clock) with text curved
along the bezel via `drawRadialText` and a vector font. Since that API is unsupported on some
devices, it degrades automatically to vertically stacked letters rather than failing.

**Runtime capability detection.** Tone constants are probed with `Attention has :TONE_X` at
runtime, so the ringtone list contains only what the device can actually play. `playTone` is
similarly guarded — an early version omitted `has :playTone` and swallowed the resulting
exception, producing silent failure with no diagnostic.

**View-stack ordering.** Callbacks after passcode entry must run *after* the view is popped.
Running them first meant a `switchToView` replaced the passcode view and the subsequent
`popView` undid it — a correct code appeared to do nothing.

---

## Data model

Alarms are stored as an array of Dictionaries in `Application.Storage`, with short keys to
minimise persisted size:

| Key | Type | Meaning |
|---|---|---|
| `id` | Number | Unique, monotonically increasing |
| `on` | Boolean | Enabled |
| `h` / `m` | Number | Hour (0–23) / minute |
| `days` | Number | Day bitmask, bit 0 = Sunday |
| `label` | String | User-facing label |
| `win` | Number | Sleep Cycle Window (minutes) |
| `mode` | Number | Alert mode |
| `snLen` / `snMax` | Number | Snooze length / max count |
| `tone` | Number | Ringtone index |
| `pc` | Boolean | Passcode required |
| `fireAt` | Number | Epoch seconds (one-time alarms) |

Repeat presets are bitmask values: `Once` = `0x00`, `4x10` = `0x1E`, `Weekdays` = `0x3E`,
`Weekend` = `0x41`, `Daily` = `0x7F`.

Per-day runtime state (fired, awake-downgraded, snooze count) is stored separately and reset
automatically at midnight, so scheduling flags never leak across days.

**Schema migration.** Every optional field is read through an accessor with a default, so an
alarm saved by an older build still loads. One case needed explicit repair: a one-time alarm
stores its trigger moment in `fireAt`, and an alarm predating that field reads back as `0` —
which the scheduler treats as "nothing scheduled". Such an alarm would sit in the list looking
enabled while being permanently unable to ring. `ensureFireAt()` detects this and rewrites a
valid time on first read.

---

## Platform constraints discovered

Documenting these because each cost real debugging time and shaped the design:

| Constraint | Consequence |
|---|---|
| Background services cannot vibrate, play tones, or self-launch | Active Alarm Mode is mandatory |
| Background polling is limited to 5-minute intervals | Foreground timer required for precision |
| Real-time sleep stages are not exposed to third-party apps | Detection built from raw heart rate |
| Custom audio files cannot be played by watch apps | Ringtones limited to built-in tones |
| Custom `ToneProfile` sequences are unsupported on this hardware | Preset tones only |
| **App alert tones are a separate device setting from alarm tones** | App can be silent while the native alarm beeps |
| The palm-cover gesture is handled by the OS before apps see input | Cannot be intercepted; disable touch overnight |
| `ActivityRecording` pins an app in the foreground | Rejected: logged the night as an activity and cost ~24% battery |
| `Attention` is not fully supported on all devices | `has` checks required before every call |
| `Activity.getActivityInfo().currentHeartRate` is null outside an activity session | Open a `Sensor` session; never rely on one HR source |
| Sensor permissions in the manifest do not start the sensor | `Sensor.setEnabledSensors` / `enableSensorEvents` must be called explicitly |
| `Toybox.Sensor` has no `disableSensorEvents()` | Stop delivery with `enableSensorEvents(null)` |
| `if (X has :madeUpName)` compiles, and is silently false forever | Guarded blocks can never run; heed the compiler's invalid-symbol warning |
| `onKeyPressed`/`onKeyReleased` fire in the simulator but often not on hardware | Hold-to-repeat input is unreliable; removed |
| A long press of UP is claimed by the system as a menu gesture | Apps cannot implement their own UP-hold shortcut |

---

## How the algorithm is verified

Testing an algorithm against the same reasoning that produced it proves very
little. Four independent checks are used instead, each able to catch failures the
others cannot:

| Check | What it would catch |
|---|---|
| **Constants parsed from `Constants.mc` at test time** | A test port that has silently drifted from the shipped source |
| **13 invariants derived from those constants** | Configurations that cannot work — e.g. a warm-up that doesn't fit before the window opens |
| **Differential testing** against a second, naive implementation (percentiles by literal sorting, no caching) | Any error in the optimised code — 21,600 tick-by-tick comparisons must match *exactly* |
| **Cross-validation** on an independently written physiology model | An algorithm that only works on the model it was tuned against |
| **Fuzzing** with adversarial streams — dead sensor, flat line, maximum oscillation, sparse nulls, monotonic ramps | Violations of the hard guarantees under inputs no real night would produce |
| **Integration simulation** of whole nights through the real call sequence, with 1–20 alarms and screens covering the view | Bugs in the seams between components, where shared singleton state is mutated from a loop or a lifecycle callback fires more often than assumed |
| **Calendar simulation** — every alarm minute of the day, all repeat masks over a full week, day rollovers, ±1 h clock shifts | Scheduling errors that only appear at midnight, on a particular weekday, or across a DST change |

### Why the bugs arrived one layer at a time

Each round of review found defects the previous round could not have, because
each round modelled a layer the previous one did not:

| Layer | Found by | Example defect |
|---|---|---|
| Detector maths | Simulation and algebra | An awake threshold above the score's ceiling |
| Monkey C / API validity | The compiler | `Sensor.disableSensorEvents()` does not exist, so a `has` guard was false forever |
| Component seams | Integration simulation | One alarm's `resetWindow()` erasing another's peak state |
| Calendar | Date-arithmetic simulation | A snooze spanning midnight being deleted |
| State machine | Ring/snooze/dismiss simulation | Dismissing one alarm disarming a backup |
| **Real hardware** | **Only a real night** | — |

The layers above are now all covered. The last one is the genuine remaining gap:
no simulation can confirm that the optical sensor actually delivers data on a
specific watch, which is exactly why the heart-rate readout was added to the
Active Alarm screen.

Two results are worth stating plainly:

- The optimised detector matches the naive reference **exactly** (0 mismatches in
  21,600 comparisons), so the incremental caching introduces no error of its own.
- The `RECALC_EVERY` optimisation — recomputing percentiles every 4th sample
  rather than every tick, to save battery — shifts the score by a mean of **0.14
  points** and leaves the wake time **identical on 85% of nights**, differing by
  at most **6 minutes** otherwise. That is a deliberate trade, now measured
  rather than assumed.

Fuzzing confirms the two guarantees that must never break, across 216 adversarial
nights: **the alarm never fires late, and never before the window opens** — including
when the heart-rate sensor returns nothing at all. The integration suite re-confirms
both across a further 480 whole-night simulations, and that wake quality is now
**identical with 20 alarms enabled as with one**.

---

## Testing

The scheduling, passcode, snooze, and detection logic are validated by executable models that
mirror the Monkey C implementation, covering paths that are impractical to exercise on-device
(a full night takes 8 hours; the suite runs in seconds).

**Over 73,000 assertions across 8 suites, 0 failures.** (Exact counts vary slightly between
runs, since several suites generate randomised scenarios.)

| Suite | Coverage | Approx. cases |
|---|---|---|
| 1–2 | Passcode acceptance, exit gating, snooze/delete state | 4,700 |
| 3 | Sleep detection, alarm firing, sound gating | 59,800 |
| 4 | Memory and runtime stability | 570 |
| 5–6 | Repeat presets, auto-exit, battery model | 2,200 |
| 7 | General alarm functionality | 3,400 |
| 8 | Code-audit regressions | 2,900 |
| 9 | Cache correctness and stale-state recovery | 2,600 |
| 10 | Time-picker stepping and navigation | 1,070 |
| 11 | Degenerate-input edge cases | 3,000 |
| 12 | Backward compatibility with older saved data | 1,250 |
| 13 | Smart wake: sensor sourcing, scoring, wake decision | 400 |
| 14 | Differential, fuzz and boundary verification of the wake decision | 160 |
| 15 | Integration: view lifecycle, multi-alarm, whole-night sequencing | 30 |
| 16 | Calendar edges, day rollover, snooze state machine, watchdog budget | 35 |
| 17 | Ring/snooze/passcode state machine and view lifecycle | 330 |

Representative coverage:

- **Exhaustive passcode sweep** — all 10,000 four-digit codes; exactly 2 accepted
- **Exhaustive button permutations** — all 1,296 four-key sequences for the exit combo
- **All 128 day-bitmask combinations** verified against every weekday
- **400 simulated nights** confirming the deadline guarantee never fails
- **100,000 randomised press sequences** producing zero accidental dismissals
- **Degenerate sensor input** — flat-line heart rate, boundary values and sub-threshold
  buffers, confirming the score never inflates into a false wake

### Bugs caught by testing

- **Snooze re-fired instantly on repeating alarms.** Snoozing left the alarm inside its
  15-minute grace window, so the base schedule re-fired it a second later. One-time alarms
  masked the bug because firing disables them.
- **Deletion removed by value.** `Array.remove()` matches on equality and could remove the
  wrong entry when two alarms matched; rebuilt by index.
- **Awake-detection could never trigger** at the 75-minute window — sampling began only 5
  minutes before the check, below the 10-minute warm-up threshold.
- **Legacy one-time alarms could never fire.** An alarm saved before the `fireAt` field
  existed read back as `0`, which the scheduler treats as unscheduled — so it appeared
  enabled in the list but was permanently dead.

---

## Build and install

**Requirements:** Connect IQ SDK 9.x, a Garmin developer key, VS Code with the Monkey C
extension.

```bash
# Build for the Forerunner 265S
monkeyc -o smartalarm.prg -f monkey.jungle -y /path/to/developer_key -d fr265s -w

# Run in the simulator
connectiq && monkeydo smartalarm.prg fr265s
```

**Sideload:** enable Developer Mode on the watch, connect by USB, and copy `smartalarm.prg`
to `GARMIN/APPS/`.

> **Note:** `manifest.xml` contains an application UUID. If you publish your own build to the
> Connect IQ Store, generate a new one.

**Target device.** Built and tested for the Forerunner 265S (360×360 round display). Other
Garmin devices differ in screen geometry, button layout, and sensor availability; adding them
requires updating `<iq:product>` in `manifest.xml` and re-checking layout constants.

---

## Usage

### First-time setup

1. Open the app — the main screen shows **"X Alarms On"**
2. Select **Passcode Setup** and choose a 4-digit code (default `9999`, master `1234`)
3. Select **Add Alarm** and set the time — UP/DOWN change the highlighted field, START moves
   hour → minute → AM/PM. Minutes wrap around, so **DOWN is faster for late minutes**
   (`:45` is 15 presses down, not 45 up)
4. Configure Repeat, Label, Sleep Cycle Window, Alert, Ringtone, Snooze Length, Max Snoozes
   and Passcode
5. Choose **Save and Close**

### Nightly routine

1. Make sure the alarm's **Status** is On
2. From the main screen, select **Alarm Activation Mode**
3. Leave the app in this mode and go to sleep. The screen is near-black and refreshes once a
   minute, showing the current time and next alarm
4. The alarm fires during light sleep inside your window, or at your set time at the latest

> Alarms **do not ring** unless Active Alarm Mode is running — this is the platform
> constraint described above, not an oversight.

To exit Active Alarm Mode deliberately: press **BACK, then UP**, and enter your passcode.

### When the alarm rings

- Press any button to reveal the controls
- **START** — snooze (if snoozes remain)
- **BACK then UP** — "I'm Awake!", then enter your passcode

Dismissing an alarm closes Active Alarm Mode automatically unless a snooze is pending, so the
passcode is only entered once.

### Recommended settings

| Setting | Recommendation | Reason |
|---|---|---|
| Sleep Cycle Window | 45 min | Best wake quality per minute of lost sleep |
| Alert | Vibrate Only | App tones are suppressed when the watch mutes alert tones |
| Touchscreen | Off overnight | The palm gesture exits the app and cannot be blocked in code |

> **Enable Alert Tones** (Hold UP → System → Sound & Vibe) if you want sound. This is a
> *different setting* from the alarm tone — the native alarm can beep while app tones are
> muted.

---

## Troubleshooting

| Symptom | Most likely cause | Fix |
|---|---|---|
| Alarm didn't ring at all | Active Alarm Mode wasn't running | Open it from the main screen before sleeping |
| Alarm vibrates but makes no sound | The watch's **Alert Tones** are off — a different setting from the built-in alarm's | Hold UP → System → Sound & Vibe → Alert Tones |
| Ringtone list is very short | The watch only exposes a few tones; the list is built from what it actually supports | Nothing to fix — those are all the tones available |
| App exited overnight | The palm-cover gesture returns to the watch face and cannot be intercepted by any app | Hold UP → System → Touch → turn the touchscreen off overnight |
| An alarm shows ON but never fires | It already fired today, or it's a one-time alarm that has done its job | Check **Status**; re-saving an alarm re-arms it |
| Woke at the set time, not earlier | No light-sleep moment was found in the window | Use a longer Sleep Cycle Window — 45 min or more |
| Asked for the passcode twice | Older behaviour; dismissing now closes Active Alarm Mode unless a snooze is pending | Update to the current build |
| Forgot the passcode | — | Enter the master code **1234**, or get it wrong 5 times and it fills itself in |

---

### The alarm never rings early

Open Active Alarm Mode and look at the dim `HR` line, which appears once a wake window is
within about 105 minutes.

| Readout | Meaning |
|---|---|
| `HR -- none` (amber) | No heart-rate source is responding. Check the watch is worn snugly and that wrist heart rate is enabled in the watch's own settings. |
| `HR -- live/sensor/...` (amber) | A source was reachable but returned nothing usable. |
| `HR 52  18/40` | Working, still warming up — 40 samples (~10 min) are needed before the score is trusted. |
| `HR 52  ready` | Working and armed. |

If it reads `ready` and the alarm still fires exactly on time, that is a legitimate outcome:
no sufficiently light moment was found inside the window, so the deadline governed. A longer
Sleep Cycle Window gives the detector more to work with, though 45 minutes measured best.

---

## Known limitations

**Wake windows are truncated at midnight.** The scheduler derives an alarm's target
from the current day's midnight, so the portion of a wake window falling *before*
midnight is not evaluated. An alarm at 00:30 with a 45-minute window gets 30 usable
minutes; one at exactly 00:00 gets none and simply rings on time. Alarms at 01:00
or later are unaffected, and the deadline guarantee holds at every time of day
(verified across all 1,440 possible alarm minutes). This is a deliberate trade:
fixing it means having the scheduler consider two candidate days at once, and the
added complexity in the one component that must never misfire is not worth it for
a case that only affects alarms set between midnight and 00:59.

- Alarms only fire while Active Alarm Mode is running
- The palm-cover gesture exits the app and cannot be intercepted
- Ringtones are limited to the device's built-in tones
- Sleep detection is derived from heart rate, not Garmin's own sleep staging
- Overnight battery use is significantly higher than a normal night

## License

MIT — free to use, modify and distribute, with attribution. See [LICENSE](LICENSE).
