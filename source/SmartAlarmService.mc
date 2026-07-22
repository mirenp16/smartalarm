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

        // ── 3. Evaluate every enabled alarm scheduled for today. ──────────────
        var list = AlarmStore.getAlarms();
        for (var i = 0; i < list.size(); i++) {
            var a = list[i] as Dictionary;

            if (!AlarmStore.isOn(a)) { continue; }
            if ((AlarmStore.days(a) & todayBit) == 0) { continue; }

            var aid = AlarmStore.id(a);
            if (AlarmStore.hasFired(aid)) { continue; }

            var alarmMins = AlarmStore.totalMinutes(a);
            var deadline  = alarmMins + FIRE_GRACE_MINS;

            // Too late (more than the grace period past the set time)? Mark it
            // missed so it can't ring at a random hour, and move on.
            if (nowMins > deadline) {
                AlarmStore.markFired(aid);
                continue;
            }

            // Reminder alarms (and sleep alarms downgraded because the user is
            // already awake) simply fire at the set time (within the grace window).
            if (AlarmStore.type(a) == TYPE_REMINDER || AlarmStore.isPlainFire(aid)) {
                if (nowMins >= alarmMins) {
                    fire(aid);
                    Background.exit(null);
                    return;
                }
                continue;
            }

            // ── Sleep alarm: smart wake within the Wake Window ────────────────
            var windowStart = alarmMins - AlarmStore.window(a);
            var awakeCheckAt = windowStart - AWAKE_CHECK_LEAD;

            // Before the window: if the user is clearly awake ~15 min ahead,
            // downgrade to a plain fire-on-time alarm.
            if (nowMins >= awakeCheckAt && nowMins < windowStart) {
                if (SleepDetector.isAwake()) {
                    AlarmStore.markPlainFire(aid);
                }
                continue;
            }

            // Inside the window: fire on light sleep, or at the hard deadline.
            if (nowMins >= windowStart) {
                if (nowMins >= alarmMins) {
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

    // Flags an alarm as ringing and asks the OS to surface the app.
    private function fire(alarmId as Number) as Void {
        AlarmStore.setRinging(alarmId);
        var found = AlarmStore.findById(alarmId);
        var msg = "Alarm";
        if (found[1] != null) { msg = AlarmStore.label(found[1] as Dictionary); }
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
