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
                // The snooze has been served - drop the whole thing, id included.
                AlarmStore.clearSnooze();
                return sid as Number;
            }
        }

        // Whether ANY alarm still NEEDS the detector's accumulated state.
        //
        // The detector is a singleton holding one window's peak and one awake
        // streak, but this loop visits every enabled alarm. resetWindow() used to
        // be called from inside the loop by every alarm that was NOT in its
        // window - including alarms days away. With two alarms enabled (a weekday
        // one and a weekend one, say), the far-off alarm wiped _best on every
        // single tick, so "score has fallen PEAK_DROP below its peak" could never
        // become true and peak detection was dead. Measured over 40 nights:
        // average wake lead collapsed from 21.4 min with one alarm to 4.4 min
        // with two, leaving only the last-10%-of-window fallback.
        //
        // The reset is therefore deferred until the whole list has been examined.
        //
        // It is "needs the detector", NOT "is inside a window", and the
        // difference is not cosmetic - it was a second, quieter version of the
        // same bug. The pre-window awake check below runs in the fifteen minutes
        // BEFORE a window opens, and it needs a streak of consecutive awake
        // readings to build up. That branch left this flag false, so resetWindow()
        // ran at the end of every tick and zeroed the streak, which could
        // therefore never reach AWAKE_CONFIRM_TICKS. The downgrade it guards was
        // unreachable for the life of the app. Naming the flag after the window
        // rather than after what it protects is what let that hide in plain sight.
        var detectorNeeded = false;

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
                // ensureFireAt repairs alarms saved before "fireAt" existed,
                // which would otherwise never be able to fire.
                targetSecs = AlarmStore.ensureFireAt(a);
                if (targetSecs <= 0) { continue; }
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

            // Approaching the window: are you ALREADY up?
            //
            // If so the alarm is downgraded to a plain one and rings exactly at
            // its set time. Waking you gently is pointless when you are not
            // asleep, and firing the moment the window opens - which is what
            // happens without this - can be three quarters of an hour early. Get
            // up at 05:10 for a 06:00 alarm with a 45-minute window and the
            // in-window check would ring it at 05:16.
            //
            // The flag MUST be set here. isAwake() only reports true after
            // AWAKE_CONFIRM_TICKS consecutive readings, and that streak lives in
            // the detector state that resetWindow() clears.
            if (nowSecs >= awakeCheckSecs && nowSecs < windowStartSecs) {
                detectorNeeded = true;
                if (SleepDetector.isAwake()) { AlarmStore.markPlainFire(aid); }
                continue;
            }

            if (nowSecs >= windowStartSecs) {
                detectorNeeded = true;
                if (nowSecs >= targetSecs) { return aid; }   // hard deadline

                // Already awake INSIDE the window -> ring now.
                //
                // This check used to run only in the 15 minutes BEFORE the window
                // opened. If you woke up naturally once the window was already
                // open - say 6:42, with a 6:15-7:00 window - nothing could fire
                // until the score happened to peak or the window reached 90%, so
                // you lay there awake waiting for an alarm that stayed silent.
                // Being awake is the strongest possible signal that now is a good
                // time to wake up, so it takes priority over peak detection.
                if (SleepDetector.isAwake()) { return aid; }

                // Peak detection: wake just after the lightest moment.
                // winSecs is guarded so corrupt storage can't divide by zero.
                var progress = (winSecs > 0)
                    ? ((nowSecs - windowStartSecs).toFloat() / winSecs.toFloat())
                    : 1.0;
                if (SleepDetector.shouldWake(progress)) { return aid; }
            }
        }

        // Nothing is using the detector, so its peak and awake streak belong to
        // no alarm and are dropped. Deferred to here so one alarm cannot clear
        // the state another is still accumulating.
        if (!detectorNeeded) { SleepDetector.resetWindow(); }

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
            // NO hasFired() check here, deliberately.
            //
            // It was redundant and actively wrong. nextFireEpoch() only ever
            // returns a FUTURE occurrence, so an alarm that has already gone off
            // today resolves to tomorrow by itself. Skipping it here instead made
            // this function disagree with nextAlarm(), which has no such check -
            // so creating a 4x10 alarm for 06:00 in the evening (which marks it
            // fired for today, since today's slot has passed) showed
            // "Next Alarm 6:00 AM" beside "Duration --:--". Two functions
            // answering the same question differently is the bug; they agree now.
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
