// AlarmEngine.mc
// The shared scheduling brain. Given the current time, it decides which alarm (if
// any) should fire right now, and updates per-day state (awake-downgrade, missed,
// one-time retirement) along the way.
//
// Both the background service AND Bedside Mode call evaluate(), so they behave
// identically — only what they DO on a fire differs (background nudges with a
// prompt; Bedside Mode alerts directly).
//
// Returns the alarm id to fire, or -1 if nothing should fire yet.

import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:background)
class AlarmEngine {

    static function evaluate(nowSecs as Number) as Number {
        AlarmStore.resetIfNewDay();

        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var todayBit = 1 << (info.day_of_week - 1);
        var midnight = nowSecs - (info.hour * 3600 + info.min * 60 + info.sec);
        var graceSecs = FIRE_GRACE_MINS * 60;

        // A snoozed alarm due to re-fire?
        var snoozeUntil = AlarmStore.snoozeUntil();
        if (snoozeUntil != null && nowSecs >= snoozeUntil) {
            var sid = AlarmStore.snoozedAlarmId();
            AlarmStore.setSnoozeUntil(null);
            if (sid != null) { return sid; }
        }

        var list = AlarmStore.getAlarms();
        for (var i = 0; i < list.size(); i++) {
            var a = list[i] as Dictionary;
            if (!AlarmStore.isOn(a)) { continue; }

            var aid = AlarmStore.id(a);
            if (AlarmStore.hasFired(aid)) { continue; }

            var days = AlarmStore.days(a);
            var oneTime = (days == 0);

            var targetSecs = 0;
            if (oneTime) {
                targetSecs = AlarmStore.fireAt(a);
                if (targetSecs == 0) { continue; }
            } else {
                if ((days & todayBit) == 0) { continue; }
                targetSecs = midnight + AlarmStore.totalMinutes(a) * 60;
            }

            // Past the grace period — retire it.
            if (nowSecs > targetSecs + graceSecs) {
                AlarmStore.markFired(aid);
                if (oneTime) { AlarmStore.disableById(aid); }
                continue;
            }

            // Already-awake alarms (downgraded) fire exactly on time.
            if (AlarmStore.isPlainFire(aid)) {
                if (nowSecs >= targetSecs) { return aid; }
                continue;
            }

            // Sleep alarm: smart wake within the window.
            var windowStartSecs = targetSecs - AlarmStore.window(a) * 60;
            var awakeCheckSecs = windowStartSecs - AWAKE_CHECK_LEAD * 60;

            if (nowSecs >= awakeCheckSecs && nowSecs < windowStartSecs) {
                if (SleepDetector.isAwake()) { AlarmStore.markPlainFire(aid); }
                continue;
            }

            if (nowSecs >= windowStartSecs) {
                if (nowSecs >= targetSecs) { return aid; }             // deadline
                if (SleepDetector.lightness() >= LIGHT_SLEEP_THRESHOLD) {
                    return aid;                                        // light sleep
                }
            }
        }

        return -1;
    }

    // True if any enabled alarm is currently inside (or near) its active period,
    // so Bedside Mode knows when to sample sensors vs. idle to save battery.
    static function inActiveWindow(nowSecs as Number) as Boolean {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var todayBit = 1 << (info.day_of_week - 1);
        var midnight = nowSecs - (info.hour * 3600 + info.min * 60 + info.sec);

        var list = AlarmStore.getAlarms();
        for (var i = 0; i < list.size(); i++) {
            var a = list[i] as Dictionary;
            if (!AlarmStore.isOn(a)) { continue; }
            var aid = AlarmStore.id(a);
            if (AlarmStore.hasFired(aid)) { continue; }

            var days = AlarmStore.days(a);
            var targetSecs = 0;
            if (days == 0) {
                targetSecs = AlarmStore.fireAt(a);
                if (targetSecs == 0) { continue; }
            } else {
                if ((days & todayBit) == 0) { continue; }
                targetSecs = midnight + AlarmStore.totalMinutes(a) * 60;
            }

            var win = AlarmStore.window(a);
            var startSecs = targetSecs - (win + AWAKE_CHECK_LEAD) * 60;
            var endSecs = targetSecs + FIRE_GRACE_MINS * 60;
            if (nowSecs >= startSecs && nowSecs <= endSecs) { return true; }
        }
        return false;
    }

    // The enabled alarm that will fire soonest (for the Active Alarm display), or
    // null if none are enabled/upcoming.
    static function nextAlarm(nowSecs as Number) as Dictionary? {
        var best = null;
        var bestEpoch = 0;
        var list = AlarmStore.getAlarms();
        for (var i = 0; i < list.size(); i++) {
            var a = list[i] as Dictionary;
            if (!AlarmStore.isOn(a)) { continue; }
            var e = AlarmStore.nextFireEpoch(a, nowSecs);
            if (e < 0) { continue; }
            if (best == null || e < bestEpoch) { best = a; bestEpoch = e; }
        }
        return best;
    }
}
