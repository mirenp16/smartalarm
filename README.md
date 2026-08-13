# Smart Alarm — Sleep-Cycle Alarm for Garmin

A Connect IQ watch app for the Garmin Forerunner 265S that wakes you during **light sleep**
instead of at a fixed time, using live heart-rate analysis. It adds a configurable snooze
system and a passcode gate designed to make it genuinely hard to fall back asleep.

Written in **Monkey C** against the **Connect IQ SDK 9.x**.

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
- **Tuned by simulation, not intuition.** 200 synthetic nights per configuration, calibrated
  to real exported sleep data, produced the 45-minute default via marginal-return analysis.
- **Diagnosed a fatal memory leak** from allocation counting: 1,920 font allocations per
  night reduced to 1.
- **Cut overnight workload 60–72%** with adaptive sensor sampling and a variable tick rate,
  without losing wake-time precision.
- **Turned silent failures into diagnosable ones** — a swallowed exception in the audio path
  was hiding a device setting, so capability probing and error reporting were added.

## Contents

- [What it does](#what-it-does)
- [Why Active Alarm Mode exists](#why-active-alarm-mode-exists)
- [Sleep-cycle detection](#sleep-cycle-detection)
- [Algorithm validation](#algorithm-validation)
- [Passcode system](#passcode-system)
- [Snooze model](#snooze-model)
- [Battery engineering](#battery-engineering)
- [Architecture](#architecture)
- [Data model](#data-model)
- [Platform constraints discovered](#platform-constraints-discovered)
- [Testing](#testing)
- [Build and install](#build-and-install)
- [Usage](#usage)

---

## What it does

A conventional alarm fires at a fixed time, which frequently drags you out of deep sleep —
the cause of grogginess (sleep inertia). This app instead watches a **Sleep Cycle Window**
before your set time and fires at the lightest moment it can find inside it.

| Feature | Detail |
|---|---|
| Smart wake | Fires during light sleep within a 30/45/60/75-minute window |
| Deadline guarantee | Always fires by your set time if no light moment is found |
| Already-awake detection | Skips smart wake and fires exactly on time if you're already up |
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
with a clean fallback to HR-only.

In simulation this separates sleep states cleanly:

| True state | Mean score |
|---|---|
| Deep | 16 |
| Medium-deep | 38 |
| Medium-light | 58 |
| Light | 78 |

### Wake decision

Rather than a fixed cut-off, the detector uses **peak detection** — it fires just *after*
the score crests, meaning you've passed the lightest point:

```
if best_score >= PEAK_BAR (70) and current <= best - PEAK_DROP (8):  fire
if progress >= 90% of window and current >= LATE_BAR (50):           fire
if now >= set time:                                                  fire (hard deadline)
```

A 10-minute warm-up (`MIN_HR_SAMPLES = 40`) is required before the score is trusted; until
then the detector reports "insufficient data" and the deadline governs.

---

## Algorithm validation

The detector was validated against **synthetic nights** modelling 80–105 minute sleep cycles
with randomised phase, cycle length and noise, calibrated to real exported Garmin sleep data
(6.65 h mean duration, ~4.4 cycles/night).

Wake quality is measured as sleep "lightness" at the moment of firing, where **0.47 is the
baseline** for a fixed-time alarm and 1.0 is the theoretical optimum.

| Window | Woke early | Avg minutes early | Lightness at wake |
|---|---|---|---|
| 15 min | 129/200 | 7 | 0.53 |
| 30 min | 163/200 | 16 | 0.60 |
| **45 min** | **192/200** | **27** | **0.66** |
| 60 min | 200/200 | 39 | 0.68 |
| 75 min | 200/200 | 57 | 0.71 |

**45 minutes is the default**, chosen as the knee of the curve. Marginal analysis shows each
additional 15 minutes buys +0.07, then +0.06, then the 45→60 step collapses to **+0.02 for
12 more minutes of lost sleep**. The 15-minute option was removed entirely — at 0.53 it
barely beats a fixed alarm, because there isn't enough of a sleep cycle inside it.

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

Representative coverage:

- **Exhaustive passcode sweep** — all 10,000 four-digit codes; exactly 2 accepted
- **Exhaustive button permutations** — all 1,296 four-key sequences for the exit combo
- **All 128 day-bitmask combinations** verified against every weekday
- **400 simulated nights** confirming the deadline guarantee never fails
- **100,000 randomised press sequences** producing zero accidental dismissals

### Bugs caught by testing

- **Snooze re-fired instantly on repeating alarms.** Snoozing left the alarm inside its
  15-minute grace window, so the base schedule re-fired it a second later. One-time alarms
  masked the bug because firing disables them.
- **Deletion removed by value.** `Array.remove()` matches on equality and could remove the
  wrong entry when two alarms matched; rebuilt by index.
- **Awake-detection could never trigger** at the 75-minute window — sampling began only 5
  minutes before the check, below the 10-minute warm-up threshold.

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
3. Select **Add Alarm**, set the time, then configure Repeat, Label, Sleep Cycle Window,
   Alert, Ringtone, Snooze Length, Max Snoozes and Passcode
4. Choose **Save and Close**

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

## Known limitations

- Alarms only fire while Active Alarm Mode is running
- The palm-cover gesture exits the app and cannot be intercepted
- Ringtones are limited to the device's built-in tones
- Sleep detection is derived from heart rate, not Garmin's own sleep staging
- Overnight battery use is significantly higher than a normal night

## License

MIT — free to use, modify and distribute, with attribution. See [LICENSE](LICENSE).
