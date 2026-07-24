// SmartAlarmService.mc
// The background service. The OS wakes this every ~5 minutes (Garmin's minimum)
// even while the app is closed. Each wake we decide whether any alarm should
// fire, and if so we flag it "ringing" and ask the OS to surface the app.
//
// Because a background process on Garmin cannot reliably play tones/vibrate or
// force the app open, the actual alerting (tone + vibration + snooze UI) happens
// in the foreground RingingView. This service only decides WHEN to fire and nudges
// the user via Background.requestApplicationWake().
//
// In SDK 9 ServiceDelegate lives in Toybox.System (not Toybox.Background).

import Toybox.Background;
import Toybox.System;
import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:background)
class SmartAlarmService extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        AlarmStore.resetIfNewDay();

        var info    = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var nowMins = info.hour * 60 + info.min;
        var nowSecs = Time.now().value();
        var todayBit = 1 << (info.day_of_week - 1);

        // ── 1. Something is already ringing? Keep nudging until handled. ───────
        var ringing = AlarmStore.ringingId();
        if (ringing != null) {
            requestWake("Smart Alarm");
            Background.exit(null);
            return;
        }

        // ── 2. A snoozed alarm due to re-fire? ────────────────────────────────
        var snoozeUntil = AlarmStore.snoozeUntil();
        if (snoozeUntil != null && nowSecs >= snoozeUntil) {
            var snoozedId = AlarmStore.snoozedAlarmId();
            AlarmStore.setSnoozeUntil(null);
            if (snoozedId != null) {
                fire(snoozedId);
                Background.exit(null);
                return;
            }
        }

        // ── 3. Evaluate every enabled alarm. ──────────────────────────────────
        // All timing is done in absolute epoch seconds so repeating and one-time
        // alarms share one code path.
        var midnight = nowSecs - (info.hour * 3600 + info.min * 60 + info.sec);
        var graceSecs = FIRE_GRACE_MINS * 60;

        var list = AlarmStore.getAlarms();
        for (var i = 0; i < list.size(); i++) {
            var a = list[i] as Dictionary;

            if (!AlarmStore.isOn(a)) { continue; }

            var aid = AlarmStore.id(a);
            if (AlarmStore.hasFired(aid)) { continue; }

            var days = AlarmStore.days(a);
            var oneTime = (days == 0);

            // Target time (epoch secs) for this alarm.
            var targetSecs = 0;
            if (oneTime) {
                targetSecs = AlarmStore.fireAt(a);
                if (targetSecs == 0) { continue; }
            } else {
                if ((days & todayBit) == 0) { continue; }   // not scheduled today
                targetSecs = midnight + AlarmStore.totalMinutes(a) * 60;
            }

            // Too late (past the grace period)? Retire it and move on.
            if (nowSecs > targetSecs + graceSecs) {
                AlarmStore.markFired(aid);
                if (oneTime) { AlarmStore.disableById(aid); }
                continue;
            }

            // Reminder alarms (and sleep alarms downgraded to plain) fire on time.
            if (AlarmStore.type(a) == TYPE_REMINDER || AlarmStore.isPlainFire(aid)) {
                if (nowSecs >= targetSecs) {
                    fire(aid);
                    Background.exit(null);
                    return;
                }
                continue;
            }

            // ── Sleep alarm: smart wake within the Wake Window ────────────────
            var windowStartSecs = targetSecs - AlarmStore.window(a) * 60;
            var awakeCheckSecs = windowStartSecs - AWAKE_CHECK_LEAD * 60;

            // Before the window: if clearly awake ~15 min ahead, downgrade to a
            // plain fire-on-time alarm.
            if (nowSecs >= awakeCheckSecs && nowSecs < windowStartSecs) {
                if (SleepDetector.isAwake()) {
                    AlarmStore.markPlainFire(aid);
                }
                continue;
            }

            // Inside the window: fire at the deadline, or early on light sleep.
            if (nowSecs >= windowStartSecs) {
                if (nowSecs >= targetSecs) {
                    fire(aid);                    // hard deadline reached
                    Background.exit(null);
                    return;
                }
                if (SleepDetector.lightness() >= LIGHT_SLEEP_THRESHOLD) {
                    fire(aid);                    // light sleep detected early
                    Background.exit(null);
                    return;
                }
            }
        }

        Background.exit(null);
    }

    // Flags an alarm as ringing and asks the OS to surface the app. One-time
    // alarms are switched off immediately (they've done their job).
    private function fire(alarmId as Number) as Void {
        AlarmStore.setRinging(alarmId);
        var found = AlarmStore.findById(alarmId);
        var msg = "Alarm";
        if (found[1] != null) {
            var fa = found[1] as Dictionary;
            msg = AlarmStore.label(fa);
            if (AlarmStore.days(fa) == 0) { AlarmStore.disableById(alarmId); }
        }
        requestWake(msg);
    }

    // requestApplicationWake shows a system prompt (and buzzes on most devices)
    // asking to open the app. Wrapped in try/catch so an unsupported device can
    // never crash the service.
    private function requestWake(msg as String) as Void {
        try {
            Background.requestApplicationWake(msg);
        } catch (e) {
            // Device doesn't support programmatic wake — nothing else we can do
            // from the background. The alarm will show next time the app opens.
        }
    }
}
