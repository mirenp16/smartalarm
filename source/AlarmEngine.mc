// AlarmEngine.mc
// The shared scheduling brain. Given the current time, it decides which alarm (if
// any) should fire right now, and updates per-day state (awake-downgrade, missed,
// one-time retirement) along the way.
//
// evaluate() is the single source of truth for "should something ring right now?".
// Active Alarm Mode calls it on every tick.
//
// Returns the alarm id to fire, or -1 if nothing should fire yet.

import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

class AlarmEngine {

    static function evaluate(nowSecs as Number) as Number {
        AlarmStore.resetIfNewDay();

        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var todayBit = 1 << (info.day_of_week - 1);
        var midnight = nowSecs - (info.hour * 3600 + info.min * 60 + info.sec);
        var graceSecs = FIRE_GRACE_MINS * 60;

        // A snoozed alarm due to re-fire? (validSnoozeId drops snoozes whose
        // alarm has since been deleted, so a ghost can't fire.)
        var sid = AlarmStore.validSnoozeId();
        if (sid != null) {
            var until = AlarmStore.snoozeUntil();
            if (until != null && nowSecs >= until) {
                AlarmStore.setSnoozeUntil(null);
                return sid as Number;
            }
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
            var winSecs = AlarmStore.window(a) * 60;
            var windowStartSecs = targetSecs - winSecs;
            var awakeCheckSecs = windowStartSecs - AWAKE_CHECK_LEAD * 60;

            if (nowSecs >= awakeCheckSecs && nowSecs < windowStartSecs) {
                if (SleepDetector.isAwake()) { AlarmStore.markPlainFire(aid); }
                continue;
            }

            if (nowSecs >= windowStartSecs) {
                if (nowSecs >= targetSecs) { return aid; }   // hard deadline
                // Peak detection: wake just after the lightest moment.
                // winSecs is guarded so corrupt storage can't divide by zero.
                var progress = (winSecs > 0)
                    ? ((nowSecs - windowStartSecs).toFloat() / winSecs.toFloat())
                    : 1.0;
                if (SleepDetector.shouldWake(progress)) { return aid; }
            } else {
                SleepDetector.resetWindow();
            }
        }

        return -1;
    }

    // Seconds until the next alarm needs attention, or -1 if nothing is pending.
    // Used to decide how hard the app should work: for most of the night there
    // is nothing to do but watch the clock.
    static function secsUntilNextTarget(nowSecs as Number) as Number {
        var soonest = -1;
        var list = AlarmStore.getAlarms();
        for (var i = 0; i < list.size(); i++) {
            var a = list[i] as Dictionary;
            if (!AlarmStore.isOn(a)) { continue; }
            if (AlarmStore.hasFired(AlarmStore.id(a))) { continue; }
            var e = AlarmStore.nextFireEpoch(a, nowSecs);
            if (e < 0) { continue; }
            var d = e - nowSecs;
            if (soonest < 0 || d < soonest) { soonest = d; }
        }
        var sn = AlarmStore.snoozeUntil();
        if (sn != null) {
            var ds = sn - nowSecs;
            if (ds >= 0 && (soonest < 0 || ds < soonest)) { soonest = ds; }
        }
        return soonest;
    }

    // Should we be reading the heart-rate sensor yet? Sampling all night wastes
    // battery: the detector only needs about an hour of history to build a
    // baseline, so it stays idle until the wake window is approaching.
    //
    // Takes a pre-computed distance so the caller can work it out ONCE per tick.
    // Calling secsUntilNextTarget() separately from here and from the timer-rate
    // logic doubled an already expensive scan.
    static function shouldSampleAt(secsUntil as Number) as Boolean {
        if (secsUntil < 0) { return false; }
        return secsUntil <= (MAX_WINDOW_MINS + SAMPLE_LEAD_MINS) * 60;
    }

    // The alarm that governs "are we still on duty?" - used for the Next Alarm
    // display and the passcode gate.
    //
    // A SNOOZED alarm counts, and takes priority. Without this, snoozing a
    // one-time alarm switched it off, nextAlarm() returned null, and you could
    // walk out of Active Alarm Mode with no passcode - exactly the snooze bug.
    static function governingAlarm(nowSecs as Number) as Dictionary? {
        var sid = AlarmStore.validSnoozeId();
        if (sid != null) {
            var found = AlarmStore.findById(sid as Number);
            if (found[1] != null) { return found[1] as Dictionary; }
        }
        // An alarm that is currently ringing also keeps us on duty.
        var rid = AlarmStore.ringingId();
        if (rid != null) {
            var r = AlarmStore.findById(rid as Number);
            if (r[1] != null) { return r[1] as Dictionary; }
        }
        return nextAlarm(nowSecs);
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
