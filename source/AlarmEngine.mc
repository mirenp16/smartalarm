// AlarmEngine.mc
// The shared scheduling brain. Given the current time, it decides which alarm (if
// any) should fire right now, retiring expired one-time alarms along the way.
//
// evaluate() is the single source of truth for "should something ring right now?".
// Active Alarm Mode calls it on every tick.
//
// Returns the alarm id to fire, or -1 if nothing should fire yet.

import Toybox.Lang;

class AlarmEngine {

    private static var _lastAt as Number = 0;
    private static var _lastWall as Number = 0;
    private static var _lastOffset as Number = 0;
    private static var _jumpFrom as Number = 0;
    private static var _jumpTo as Number = 0;
    private static var _jumpAt as Number = 0;
    static function resetClock() as Void { _lastAt = 0; _jumpAt = 0; }

    static function crossedByClockChange(key as Number, now as Number) as Boolean {
        var age = now-_jumpAt;
        return _jumpAt > 0 && age >= 0 && age <= FIRE_GRACE_MINS*60
            && key > _jumpFrom && key <= _jumpTo;
    }

    static function evaluate(nowSecs as Number) as Number {
        AlarmStore.ensureState();

        var offset = AlarmClock.offset(nowSecs);
        var wall = nowSecs + offset;
        var day = wall / 86400;
        var gap = nowSecs - _lastAt;
        var jumped = _lastAt > 0 && gap >= 0 && gap <= 120 && offset > _lastOffset;
        var previousWall = _lastWall;
        if (jumped) { _jumpFrom = previousWall; _jumpTo = wall; _jumpAt = nowSecs; }
        _lastAt = nowSecs;
        _lastWall = wall;
        _lastOffset = offset;
        var graceSecs = FIRE_GRACE_MINS * 60;

        // A snoozed alarm due to re-fire? (validSnoozeId drops snoozes whose
        // alarm has since been deleted, so a ghost can't fire.)
        var sid = AlarmStore.validSnoozeId();
        if (sid != null) {
            var until = AlarmStore.snoozeUntil();
            if (until != null && nowSecs >= until) {
                // The snooze has been served - drop the whole thing, id included.
                AlarmStore.clearSnooze();
                return AlarmStore.prepareRing(sid as Number, 0, true);
            }
        }

        // Keep peak history while any alarm is inside its wake window.
        var detectorNeeded = false;
        var selected = -1;
        var selectedKey = 0;
        var selectedTarget = 0;

        var list = AlarmStore.getAlarms();
        for (var i = 0; i < list.size(); i++) {
            var a = list[i] as Dictionary;
            if (!AlarmStore.isOn(a)) { continue; }

            var aid = AlarmStore.id(a);

            var days = AlarmStore.days(a);
            var oneTime = (days == 0);

            // Yesterday retains its after-midnight grace period. Tomorrow's
            // window can begin tonight. Identity always belongs to the TARGET.
            for (var off = -1; off <= 1; off++) {
                if (oneTime && off != 0) { continue; }
                if (!oneTime && (days & AlarmClock.dayBit(day+off)) == 0) { continue; }
                var key = AlarmClock.targetKey(day+off,AlarmStore.totalMinutes(a));
                var targetSecs = oneTime ? AlarmStore.ensureFireAt(a) : key-offset;
                if (oneTime) { key = targetSecs+offset; }
                if (AlarmStore.occurrenceDone(aid,key)) { continue; }
                var crossed = crossedByClockChange(key,nowSecs);
                if (nowSecs > targetSecs+graceSecs && !crossed) {
                    // Only one-time alarms need retirement. Old repeating dates
                    // naturally fall out of the three-day candidate range.
                    if (oneTime) { AlarmStore.disableById(aid); }
                    continue;
                }
                var winSecs = AlarmStore.window(a)*60;
                var start = targetSecs-winSecs;
                if (nowSecs < start) { continue; }
                detectorNeeded = true;
                var fire = nowSecs >= targetSecs;
                if (!fire) {
                    var progress = winSecs > 0 ? (nowSecs-start).toFloat()/winSecs : 1.0;
                    fire = SleepDetector.isAwake() || SleepDetector.shouldWake(progress);
                }
                if (fire && (selected < 0 || targetSecs < selectedTarget)) {
                    selected = aid; selectedKey = key; selectedTarget = targetSecs;
                }
            }
        }

        // Nothing is using the detector, so its peak belongs to
        // no alarm and is dropped. Deferred to here so one alarm cannot clear
        // the state another is still accumulating.
        if (!detectorNeeded) { SleepDetector.resetWindow(); }

        if (selected >= 0) { return AlarmStore.prepareRing(selected,selectedKey,false); }

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
            // nextFireEpoch owns occurrence filtering for both UI and sampling.
            var e = AlarmStore.nextFireEpoch(a, nowSecs);
            if (e < 0) { continue; }
            var d = e > nowSecs ? e-nowSecs : 0;
            if (soonest < 0 || d < soonest) { soonest = d; }
        }
        var sn = AlarmStore.snoozeUntil();
        if (sn != null) {
            var ds = sn > nowSecs ? sn-nowSecs : 0;
            if (soonest < 0 || ds < soonest) { soonest = ds; }
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
