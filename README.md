# Smart Alarm for Garmin Forerunner 265S

A Connect IQ app that looks for a wake opportunity before your alarm time using
heart-rate trends and recent steps. It does not read Garmin Connect sleep stages
or reliably distinguish quiet wakefulness from sleep.

## Set an alarm

1. Choose **Add Alarm**, set the time and options, then **Save**.
2. For an existing alarm, change its settings and choose **Done** or press BACK
   to save. Opening its settings alone does not rearm it.
3. At bedtime, open **Active Alarm Mode** and leave the app running.

**The app has no background alarm service.** Closing it or shutting down the
watch stops alarm checks. Use a native Garmin backup alarm while validating it.

For a **6:00 am alarm with a 45-minute window**, early ringing is allowed from
**5:15 am**. Recent walking, sustained elevated heart rate, or a qualifying sleep
score can trigger it within that window. Otherwise, the initial ring is due at
**6:00**, even without sensor data or a completed warm-up.

Checks normally run every 15 seconds near the alarm, so ringing can be delayed
by up to one normal timer tick. Snoozing starts a separate delay that can end
after the original alarm time.

## Controls and settings

| Setting or action | Options or behavior |
|---|---|
| Sleep Cycle Window | 30, 45, 60, or 75 minutes; default 45 |
| Repeat | Once, Daily, Mon–Thu (4x10), Weekdays, Weekend, or Custom |
| Alert | Vibrate Only (default), Sound Only, or Sound + Vibrate |
| Snooze Length | 1, 3, 5, 10, or 15 minutes; default 5 |
| Max Snoozes | 0, 1, 2, 3, 4, 5, or 10; default 3; 0 disables snooze |
| Saved alarms | Up to 20 |
| Snooze while ringing | Press START to reveal controls, then START again |
| Dismiss or exit Active Alarm Mode | BACK then UP; enter the passcode if enabled |
| Passcode entry | UP/DOWN changes a digit; START advances or submits |
| Default passcode | `0000`; change it in Passcode Setup |
| Recovery code | `1234`; shown and prefilled after five wrong attempts |

Passcodes are enabled by default and provide wake-up friction, not security.
The alarm keeps alerting during dismissal code entry. An exit code prompt also
continues checking for due alarms. A backup alarm within two hours keeps Active
Alarm Mode open after dismissal.

Preview your ringtone and verify sound and vibration on the watch before relying
on them; device settings can affect alerts.

## Sleep longer after an early dismissal

A repeating alarm stays **ON** for future repeats after you dismiss it. To rearm
today's dismissed alarm, reopen **Active Alarm Mode**:

| When you reopen it for a dismissed 6:00 alarm | Result |
|---|---|
| Before 6:00, including 5:59 or 5:59:59 | Rearms for 6:00 today; no new warm-up required |
| At or after 6:00 | Leaves that occurrence completed; waits for the next scheduled repeat |

A rearmed occurrence waits for the set time even if awake readings remain.
Later repeats use the normal sleep-cycle window. A pending snooze or recent
ringing resumes instead of being rearmed.

A Once alarm switches **OFF** when it first rings. To reuse it, turn Status ON
and save, then open Active Alarm Mode. It schedules the next selected time and
uses the normal sleep-cycle window.

## Interruptions and clock changes

After an interruption, reopen Active Alarm Mode. It can resume ringing within
15 minutes of the ring start and a pending snooze up to 15 minutes after its
deadline. Older recovery state is discarded. Confirming an exit cancels pending
ringing and snooze, but keeps saved alarm settings.

Wake windows can cross midnight: a Thursday 12:30 am alarm with a 45-minute
window can ring from Wednesday 11:45 pm. Dismissal normally completes that
scheduled occurrence across midnight and restarts; explicit rearming before
the target follows the rule above. Snooze counts survive midnight.

Alarms follow the watch's local time when its time-zone offset changes.
Snoozes retain their elapsed-time deadline. Countdowns use the current offset;
the app does not predict future daylight-saving or time-zone changes.

If active checks observe a forward offset change no more than two minutes apart,
a skipped alarm can ring on the next check, with 15 minutes of recovery grace.
Only one alarm rings at a time. Another due alarm remains eligible for 15 minutes
after its target, or after an observed forward jump, and can expire while the
first alarm is sounding.

## Heart-rate status and wake detection

Regular sampling starts within 105 minutes of the next target. The status shows
warm-up progress such as `18/40`; `ready` means enough fresh data is available,
not that sleep detection is accurate. Outside that period, the app briefly
checks heart rate rather than sampling continuously.

The detector keeps up to 240 readings and needs 40 accepted readings for scoring
(about 10 minutes at the normal 15-second cadence). Early wake can use:

- At least 12 new steps within three minutes, with evidence expiring after
  three minutes.
- Sustained heart rate relative to the session's lowest baseline.
- A recent peak and decline in the heart-rate-based score, or a qualifying
  score near the end of the window. Recent stress data may raise the score.

These are heuristics, not validated sleep staging. Quiet sitting, low awake
heart rate, or waking before sampling starts can evade detection. Missing or
stale heart-rate data prevents HR-based early wake, but does not delay the
set-time deadline. Old walking evidence expires because you may return to sleep.

## Build and install

Tested with Java and Connect IQ SDK **9.2.0**, targeting `fr265s`. Build with your
Garmin developer signing key:

```bash
cd ~/Documents/GitHub/smartalarm
CIQ_SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
"$CIQ_SDK/bin/monkeyc" -f monkey.jungle -d fr265s -w -r \
  -y /absolute/path/to/your/developer_key.der -o smartalarm.prg
```

Replace the key path with the key used for your existing installation. Transfer
`smartalarm.prg` to the watch's `GARMIN/APPS/` folder using your Garmin USB
transfer workflow. Replace this app's file; do not delete other apps or settings.
After installing, check your saved alarm settings and reopen Active Alarm Mode.

## Tests

```bash
cd ~/Documents/GitHub/smartalarm
python3 scripts/test.py 3
```

This builds release and test executables and runs **39 native Monkey C tests**
three times in the Garmin simulator. The runner uses the configured SDK, or
`CIQ_SDK` if set. Generated logs, binaries, and `verification.json` go in
`bin/validation/`. Its generated signing key is for local tests, not your existing
watch installation.

See [verification notes](docs/review-2026-09.md) for coverage, evidence, and watch
checks. Simulator tests do not replace an overnight test on your 265S.

## License

MIT. See [LICENSE](LICENSE).
