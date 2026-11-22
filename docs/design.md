# Design and testing

Smart Alarm combines a fixed alarm deadline with an optional early-wake window.
The watch app owns scheduling, sensor sampling, alerting, and saved settings.

## Architecture

| Component | Responsibility |
|---|---|
| `AlarmClock` | Local calendar coordinates and current time-zone offset |
| `AlarmEngine` | Select the eligible alarm, enforce deadlines, and determine when sampling is needed |
| `AlarmStore` | Persist alarms, completed occurrences, ringing, and snooze state |
| `SleepDetector` | Collect sensor input and estimate early-wake opportunities |
| `BedsideView` | Run Active Alarm Mode, display status, and drive periodic checks |
| `RingingView` and `PasscodeView` | Alert, snooze, dismiss, and confirm exit |
| Menus and pickers | Create alarms and edit a working copy before saving |

## Scheduling and state

The scheduler first handles a due snooze, then selects the earliest eligible
regular target. An alarm may ring early only inside its configured wake window.
At the set time, the deadline takes priority over sensor availability, warm-up,
and score. Checks normally run every 15 seconds near the target.

Each scheduled occurrence belongs to its target's local date and time, even
when its wake window begins the previous evening. Recording completion before
showing the ringing screen prevents ordinary duplicate rings after a restart.
The store retains eight completed occurrences per alarm.

Repeating alarms remain enabled for future scheduled days; Once alarms switch
off when they ring. Snooze is a separate elapsed-time deadline. Reopening Active
Alarm Mode before a dismissed repeat's target explicitly rearms that occurrence
for the set time, bypassing early-wake scoring. Reopening at or after the target
leaves it completed. Recent ringing and pending snoozes resume first.

Settings, completion records, and session state persist locally. Reentry can
recover ringing within 15 minutes of its start and snooze up to 15 minutes after
its deadline. Confirmed exit cancels pending ringing and snooze while retaining
alarm settings.

## Wake detection and power use

The detector uses a bounded buffer of 240 heart-rate readings, with 40 accepted
readings required for scoring. It combines relative heart-rate elevation and
variability; recent stress data can raise the score. Sustained elevated heart
rate or recent walking can also indicate a wake opportunity. Walking evidence
and score peaks expire so old activity does not justify a later early ring.

The detector checks freshness, breaks awake streaks on missing data, and
recalibrates after long gaps. Its score is a heuristic, not a measured sleep
stage. Quiet wakefulness and physical sensor errors remain limitations.

Regular sampling begins within 105 minutes of the next target. Outside that
period, a brief heart-rate check supplies status without continuous sampling.
Timers use a slower cadence away from alarms, and views release sensors when
sampling is no longer needed. There is no background alarm service: the user
must leave Active Alarm Mode running. The exit passcode prompt continues alarm
checks, and ringing continues during dismissal code entry.

## Local time and recovery

Calendar targets use the watch's current local offset. Snooze keeps its elapsed
duration across offset changes. The app does not predict future transition
rules. If active checks observe a forward offset change no more than two minutes
apart, skipped targets remain eligible for 15 minutes after that change.

Only one alarm rings at a time. Other due alarms remain eligible for 15 minutes
after their target or an observed forward jump, and may expire while another
alarm is sounding. Retained completion history covers ordinary repeated hours
and adjacent dates, not unlimited backward travel. A legacy Once alarm without
a saved offset acquires the current offset during migration.

## Validation

Run `python3 scripts/test.py 3` from the repository. The runner builds release
and test executables for `fr265s`, then runs native Monkey C tests against the
production scheduler, store, and detector with a controlled clock and synthetic
sensor inputs. Test helpers are excluded from release builds.

Coverage includes wake-window boundaries, awake and walking input, stale or
missing readings, warm-up, peak expiry, deadlines, rearming, snooze and ringing
recovery, midnight windows, offset changes, repeat masks, editing, deletion,
passcodes, picker bounds, and the 20-alarm capacity.

The November 22, 2026 validation on SDK **9.2.0** passed **39 tests in each of
three runs (117 test executions)**. Both builds completed without warnings.
The tested source, resources, build settings, and runner still match the saved
verification hashes; documentation is checked separately.

Generated evidence lives under `bin/validation/`:

| Output | Contents |
|---|---|
| `tests-1.log` through `tests-3.log` | Complete simulator results |
| `verification.json` | Run/test counts, input hashes, and compiled binary hashes |
| `smartalarm.prg` and `tests.prg` | Builds signed with the local validation key |

The runner rejects incomplete results and changes to validation inputs. It uses
a content-specific executable filename, checks the passing footer and expected
test count, and retries connection failures rather than failed tests.

Simulator tests do not establish physical sensor accuracy, overnight battery
use, sound/vibration, or every UI transition. On the Forerunner 265S, verify early
wake, the set-time deadline, snooze, passcode dismissal, session recovery, and an
overnight run with normal settings. Use a native Garmin backup during validation.
