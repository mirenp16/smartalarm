# Smart Alarm for Garmin Forerunner 265S

A Connect IQ watch app with a configurable early wake window, snooze, and a
passcode to dismiss an alarm. It estimates wake opportunities from heart rate
and recent walking. It does **not** read Garmin Connect's recorded sleep stages
or reliably identify whether a motionless person is awake.

## Using the alarm

1. Select **Add Alarm**, choose the time, then configure and **Save** the alarm.
2. Set Repeat, Sleep Cycle Window, Alert, Ringtone, Snooze Length, Max Snoozes,
   and Passcode as needed. Existing alarms save with **Done** or BACK.
3. At bedtime, open **Active Alarm Mode** and leave it running.
4. Confirm that the heart-rate status shows a reading. Tracking starts within
   105 minutes of the next target; `18/40` means it is warming up, and `ready`
   means enough recent input has accumulated for scoring.

Alarms are evaluated only while Active Alarm Mode or its exit passcode prompt
is running. Leaving the app, a device shutdown, or a system gesture that closes
it stops alarm evaluation. This is not a replacement for the watch's native
alarm when a guaranteed wake-up is essential.

For a **6:00 am alarm with a 45-minute window**, the earliest allowed ring is
**5:15 am**. If recent walking or sustained elevated heart rate already indicates
wakefulness, it rings on the first evaluation at or after 5:15. Otherwise it
looks for a suitable score inside the window and falls back to the set time.
The timer runs every 15 seconds near an alarm, so timing has up to one tick of
normal scheduling delay; it is not exact to the second.

### Controls and defaults

| Setting or control | Behavior |
|---|---|
| Wake windows | 30, 45, 60, or 75 minutes; default 45 |
| Repeat | Once, Daily, Mon–Thu (4x10), Weekdays, Weekend, or Custom |
| Alert | Vibrate Only by default; Sound Only and Sound + Vibrate available |
| Snooze | Default 5 minutes, at most 3 snoozes; maximum 0 disables snooze |
| Alarm capacity | 20 saved alarms |
| Default passcode | `0000`; change it in Passcode Setup |
| Recovery code | `1234`; displayed and prefilled after five wrong attempts |
| While ringing | Any button reveals controls; START then snoozes |
| Dismiss / exit Active Alarm Mode | BACK then UP; enter the passcode if enabled |

Passcodes provide wake-up friction, not security. A nearby backup alarm keeps
Active Alarm Mode open after dismissal if its target is within two hours.
The exit passcode prompt continues checking alarms; an alarm becoming due
interrupts that exit attempt and shows the ringing screen.

### Midnight and clock changes

A wake window may start the previous evening: Thursday's 12:30 am alarm with
a 45-minute window can ring from Wednesday at 11:45 pm. The app remembers the
scheduled occurrence across midnight and restarts, so an early ring does not
repeat at the deadline. Snooze counts also survive midnight.

Once and repeating alarms follow the watch's local clock when its time-zone
offset changes. A repeated hour does not ring an already-completed occurrence
again. If active evaluation observes a forward offset change, alarms skipped
by that change become due on the next check, with a 15-minute recovery period.
Snooze remains an elapsed-time deadline when the time-zone offset changes.

Countdowns use the current offset and may adjust when the watch changes it;
the app does not predict future time-zone rules. Skipped-time recovery requires
evaluation immediately before and after the change (no gap over two minutes).
Only one alarm rings at a time; another due alarm remains eligible for 15 minutes
after its target, or after an observed forward jump. Dismiss within that period
to hear the queued alarm. Completing an occurrence suppresses duplicates for
that local date even if you travel backward across time zones.

The calendar implementation uses Garmin's local and UTC conversions documented
in [Time.Gregorian](https://developer.garmin.com/connect-iq/api-docs/Toybox/Time/Gregorian.html).

Sound depends on the watch's app alert-tone settings and Do Not Disturb.
Preview a ringtone before relying on sound. A native Garmin alarm can behave
differently from a Connect IQ app under the same device settings.

## How wake detection works

Heart rate is sampled approximately every 15 seconds into a 240-reading buffer.
After 40 accepted readings, the detector computes a relative score from the
recent mean and variability. The baseline starts updating as soon as that
warm-up completes, preserving the lowest observed baseline for wake detection.

There are three early-wake paths, all gated by the configured window:

- **Sustained elevated heart rate:** the recent average is at least 1.4 times
  the session floor for four consecutive accepted samples.
- **Recent walking:** the daily step counter increases by at least 12 within
  a three-minute observation period. That evidence expires after three minutes.
  Missing counters, backward time, and counter resets invalidate evidence.
- **A sleep-score opportunity:** after 30% of the window, a recent high score
  drops by at least eight points while the current score remains at least 50.
  Peaks expire after 12 subsequent samples. In the last 10% of the window,
  a current score of at least 50 also qualifies.

The peak threshold declines from 94 toward 70 as the deadline approaches.
Optional recent stress data may increase the score, but cannot lower it.
No heart rate means no heart-rate-based early wake; recent walking may still
qualify, and the deadline does not require sensor data.

These are heuristics, not validated sleep staging. Walking is an additional
signal, not a guarantee of wakefulness. Quiet sitting, low awake heart rate,
or waking before sampling starts can still evade detection. Walking long before
the window is deliberately not remembered indefinitely, because you might
return to sleep. The `ready` label confirms input availability, not accuracy.

Garmin documents the nullable daily step counter in
[ActivityMonitor.Info](https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityMonitor/Info.html)
and sensor registration in
[Toybox.Sensor](https://developer.garmin.com/connect-iq/api-docs/Toybox/Sensor.html).

## September 2026 fixes

- Removed the pre-window rule that postponed already-awake alarms to the set time.
  Old stored downgrade flags are ignored; existing alarms are migrated automatically.
- Established the heart-rate floor during warm-up instead of first calculating
  it much later when the scheduler asked whether the user was awake.
- Added recent walking as another wake signal.
- Rejected missing/stale detector results and broke awake streaks on missing HR.
  Long interruptions require a new warm-up.
- Prevented an old high score from causing a later low-score wake.
- Kept alarm evaluation active during the exit passcode prompt.
- Released sensors after partial registration failures as well as normal sessions.
- Fixed windows crossing midnight, snooze limits across midnight, and local-time
  scheduling after daylight-saving or time-zone offset changes.
- Kept overdue backup alarms active during their grace period and prioritized
  the earliest eligible deadline when multiple alarms qualify.
- Preserved an alarm's scheduled occurrence when only its label or other
  non-scheduling settings change.

The exact cause of the reported September 24 firing at 5:38 am cannot be proven
without device logs. These changes address reproducible logic defects; they do
not establish that Garmin's recorded wake time was available to this app.

## Build and install

Requires Java, Connect IQ SDK 9.x, and your Garmin developer signing key. The
target in `manifest.xml` is `fr265s` (360 × 360).

```bash
cd ~/Documents/GitHub/smartalarm
CIQ_SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
"$CIQ_SDK/bin/monkeyc" -f monkey.jungle -d fr265s -w -r \
  -y /absolute/path/to/your/developer_key.der -o smartalarm.prg
```

Use the signing key used for your existing installation. Replace the placeholder
path above with that key's actual path. Copy the newly built `smartalarm.prg`
to the connected watch's `GARMIN/APPS/` directory using your Garmin USB transfer
workflow. Replacing the same app file updates it; do not delete unrelated apps
or watch settings. Open Smart Alarm and verify the saved alarm settings after
installation, then enter Active Alarm Mode again.

## Reproducible tests

```bash
cd ~/Documents/GitHub/smartalarm
python3 scripts/test.py 3
```

The script builds release code and a test executable, starts the Garmin simulator,
and runs 30 native Monkey C regression tests three times. `CIQ_SDK` can override
the SDK path. Generated files and logs go under `bin/validation/`; its generated
signing key is for local validation, not your existing watch installation.

Tests exercise production code for pre-window wakefulness, walking, missing HR,
warm-up and buffer bounds, peak expiry, deadlines for all four window sizes,
snooze, deletion, repeat masks, passcodes, editing, midnight windows, daylight
saving, time-zone changes, state migration, and the 20-alarm capacity. A timed
synthetic replay checks baseline collection from 4:15, elevated HR from 4:36,
and firing at 5:15 for a 6:00 alarm. The repeat test checks
all 127 nonempty masks across seven day offsets. Synthetic inputs do not prove
sleep-stage accuracy or replace an overnight test on the real watch.

See [review and verification notes](docs/review-2026-09.md) for coverage and
remaining limitations. Earlier README assertion counts referred to tests absent
from this checkout; they are not evidence for this version.

## License

MIT. See [LICENSE](LICENSE).
