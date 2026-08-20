// AlarmStore.mc
// The data layer. Manages the list of alarms plus per-day runtime state and the
// "currently ringing" state. Everything is persisted with Application.Storage so
// it survives app restarts.
//
// An alarm is stored as a Dictionary with short keys to save space:
//   "id"    Number   unique id
//   "on"    Boolean  enabled?
//   "h"     Number   hour (0-23)
//   "m"     Number   minute (0-59)
//   "days"  Number   day bitmask (see Constants.mc)
//   "label" String   user-facing label
//   "win"   Number   wake-window minutes (sleep alarms only)
//   "mode"  Number   MODE_BOTH / MODE_SOUND / MODE_VIBE
//   "snLen" Number   snooze length in minutes
//   "snMax" Number   maximum snoozes allowed
//   "tone"  Number   index into Ringtone.names()
//   "pc"    Boolean  require the passcode to dismiss this alarm
//   "fireAt" Number  epoch seconds for one-time alarms

import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

class AlarmStore {

    // ── In-memory caches ─────────────────────────────────────────────────────
    // Persistent storage reads deserialise the whole alarm array, and
    // Gregorian.info() is a system call. The overnight tick used to trigger ~87
    // storage reads and ~63 calendar conversions EVERY tick, which trips
    // Connect IQ's instruction watchdog and kills the app ("IQ!" screen).
    // These caches reduce that to roughly one of each per minute.
    private static var _alarmCache = null;      // Array or null when dirty
    private static var _dayStateCache = null;   // Dictionary or null when dirty
    private static var _ctxMinute as Number = -1;
    private static var _ctxMidnight as Number = 0;
    private static var _ctxDow as Number = 0;   // 0 = Sunday

    // Called whenever anything is written, so nothing can serve stale data.
    static function invalidate() as Void {
        _alarmCache = null;
        _dayStateCache = null;
    }

    // Midnight (epoch secs) and day-of-week for "now", computed at most once a
    // minute instead of once per alarm per call.
    static function dayContext(nowSecs as Number) as Array<Number> {
        var minute = nowSecs / 60;
        if (minute != _ctxMinute) {
            var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            _ctxMidnight = nowSecs - (info.hour * 3600 + info.min * 60 + info.sec);
            _ctxDow = info.day_of_week - 1;     // Gregorian: 1=Sun -> 0=Sun
            _ctxMinute = minute;
        }
        return [_ctxMidnight, _ctxDow];
    }

    // ── Alarm list CRUD ──────────────────────────────────────────────────────

    static function getAlarms() as Array {
        if (_alarmCache != null) { return _alarmCache as Array; }
        var v = Application.Storage.getValue(KEY_ALARMS);
        _alarmCache = (v == null) ? [] : (v as Array);
        return _alarmCache as Array;
    }

    static function saveAlarms(list as Array) as Void {
        Application.Storage.setValue(KEY_ALARMS, list);
        _alarmCache = list;
        _dayStateCache = null;
    }

    // Builds a brand-new alarm Dictionary with sensible defaults.
    // Default days = 0 means "one-time" (fires once at the next 6:00, then off).
    static function newAlarm() as Dictionary {
        return {
            "id"     => nextId(),
            "on"     => true,
            "h"      => 6,
            "m"      => 0,
            "days"   => 0,
            "label"  => "Wake Up!",
            "win"    => DEFAULT_WINDOW,   // 45 minutes
            "mode"   => DEFAULT_ALERT_MODE,   // Vibrate Only
            "snLen"  => DEFAULT_SNOOZE_MINUTES,   // 5 minutes
            "snMax"  => DEFAULT_MAX_SNOOZE,       // 3 snoozes
            "tone"   => DEFAULT_RINGTONE,         // "Alert"
            "pc"     => DEFAULT_PASSCODE_ON,      // require passcode to get up
            "fireAt" => nextOccurrence(6, 0)
        };
    }

    // Per-alarm snooze settings (fall back to defaults for older saved alarms).
    static function snoozeLen(a as Dictionary) as Number { return _n(a, "snLen", DEFAULT_SNOOZE_MINUTES); }
    static function maxSnoozeOf(a as Dictionary) as Number { return _n(a, "snMax", DEFAULT_MAX_SNOOZE); }
    static function ringtone(a as Dictionary) as Number { return _n(a, "tone", DEFAULT_RINGTONE); }
    static function passcodeOn(a as Dictionary) as Boolean { return _b(a, "pc", DEFAULT_PASSCODE_ON); }

    // ── Global passcode (plain text - it's friction, not security) ───────────

    static function passcode() as String {
        var v = Application.Storage.getValue(KEY_PASSCODE);
        return (v != null) ? v as String : DEFAULT_PASSCODE;
    }

    static function setPasscode(code as String) as Void {
        Application.Storage.setValue(KEY_PASSCODE, code);
    }

    // Accepts the user's code or the master code.
    static function checkPasscode(entered as String) as Boolean {
        return entered.equals(passcode()) || entered.equals(MASTER_PASSCODE);
    }

    // How many saved alarms are enabled (for the "X Alarms On" header).
    static function countOn() as Number {
        var list = getAlarms();
        var c = 0;
        for (var i = 0; i < list.size(); i++) {
            if (isOn(list[i] as Dictionary)) { c++; }
        }
        return c;
    }

    static function isFull() as Boolean { return getAlarms().size() >= MAX_ALARMS; }

    // Epoch seconds of the next time this alarm will fire (repeating: scans up to
    // 7 days ahead for a scheduled day; one-time: its fireAt). -1 if none.
    static function nextFireEpoch(a as Dictionary, nowSecs as Number) as Number {
        var d = days(a);
        if (d == 0) {
            var fa = ensureFireAt(a);   // repairs a legacy alarm with no fireAt
            return (fa > nowSecs) ? fa : -1;
        }
        // Uses the cached day context - this used to call Gregorian.info() once
        // per alarm per lookup, which is what overloaded the watchdog.
        var ctx = dayContext(nowSecs);
        var midnight = ctx[0];
        var dow = ctx[1];
        var secOfDay = totalMinutes(a) * 60;
        for (var off = 0; off < 8; off++) {
            var epoch = midnight + off * 86400 + secOfDay;
            if (epoch <= nowSecs) { continue; }
            var bit = (dow + off) % 7;
            if ((d & (1 << bit)) != 0) { return epoch; }
        }
        return -1;
    }

    // Epoch seconds of the next time the clock reads h:m (today if still ahead,
    // otherwise tomorrow). Used for one-time alarms.
    static function nextOccurrence(h as Number, m as Number) as Number {
        var now = Time.now();
        var info = Gregorian.info(now, Time.FORMAT_SHORT);
        var midnight = now.value() - (info.hour * 3600 + info.min * 60 + info.sec);
        var t = midnight + h * 3600 + m * 60;
        if (t <= now.value()) { t += 86400; }
        return t;
    }

    static function fireAt(a as Dictionary) as Number {
        return _n(a, "fireAt", 0);
    }

    // MIGRATION SAFETY.
    // A one-time alarm stores its trigger moment in "fireAt". An alarm saved by
    // an older build can lack that field entirely, which reads back as 0 - and 0
    // is treated as "nothing scheduled", so the alarm would sit in the list
    // looking enabled while being permanently unable to fire, with no warning.
    // Repair it the first time we look at it.
    static function ensureFireAt(a as Dictionary) as Number {
        var fa = fireAt(a);
        if (fa > 0) { return fa; }
        fa = nextOccurrence(hour(a), minute(a));
        a.put("fireAt", fa);
        var found = findById(id(a));
        var idx = found[0] as Number;
        if (idx >= 0) { updateAlarm(idx, a); }
        return fa;
    }

    static function addAlarm(alarm as Dictionary) as Void {
        var list = getAlarms();
        list.add(alarm);
        saveAlarms(list);
    }

    static function updateAlarm(index as Number, alarm as Dictionary) as Void {
        var list = getAlarms();
        if (index >= 0 && index < list.size()) {
            list[index] = alarm;
            saveAlarms(list);
        }
    }

    static function deleteAlarm(index as Number) as Void {
        var list = getAlarms();
        if (index >= 0 && index < list.size()) {
            var doomed = id(list[index] as Dictionary);
            // Rebuild by index rather than Array.remove(), which deletes by
            // value and could pick the wrong entry if two alarms ever matched.
            var kept = [];
            for (var i = 0; i < list.size(); i++) {
                if (i != index) { kept.add(list[i]); }
            }
            saveAlarms(kept);
            // Clear any pending snooze / ringing state that belonged to it,
            // otherwise its snooze time keeps showing up as the Next Alarm.
            clearStateFor(doomed);
        }
    }

    // Drops snooze + ringing state for an alarm that no longer exists (or is off).
    static function clearStateFor(alarmId as Number) as Void {
        if (snoozedAlarmId() == alarmId) {
            Application.Storage.setValue(KEY_SNOOZE_ID, null);
            Application.Storage.setValue(KEY_SNOOZE_UNTIL, null);
        }
        if (ringingId() == alarmId) {
            Application.Storage.setValue(KEY_RING_ID, null);
        }
    }

    // A snooze is only valid while its alarm still exists AND is enabled.
    static function validSnoozeId() as Number or Null {
        var until = snoozeUntil();
        if (until == null) { return null; }
        var sid = snoozedAlarmId();
        if (sid == null) { return null; }
        var found = findById(sid as Number);
        if (found[1] == null) {
            clearStateFor(sid as Number);   // alarm was deleted - forget the snooze
            return null;
        }
        return sid;
    }

    // Returns a unique, ever-increasing id.
    static function nextId() as Number {
        var id = Application.Storage.getValue(KEY_NEXT_ID);
        if (id == null) { id = 1; }
        Application.Storage.setValue(KEY_NEXT_ID, id + 1);
        return id;
    }

    // ── Field accessors (read a field from an alarm dict with a default) ──────

    static function isOn(a as Dictionary)   as Boolean { return _b(a, "on", false); }
    static function hour(a as Dictionary)    as Number  { return _n(a, "h", 7); }
    static function minute(a as Dictionary)  as Number  { return _n(a, "m", 0); }
    static function days(a as Dictionary)    as Number  { return _n(a, "days", 0); }
    static function window(a as Dictionary)  as Number  { return _n(a, "win", DEFAULT_WINDOW); }
    static function mode(a as Dictionary)    as Number  { return _n(a, "mode", DEFAULT_ALERT_MODE); }
    static function label(a as Dictionary)   as String  {
        var v = a.get("label");
        return (v != null) ? v as String : "Alarm";
    }
    static function id(a as Dictionary)      as Number  { return _n(a, "id", 0); }

    // Total minutes since midnight for the alarm's set time (e.g. 7:30 -> 450).
    static function totalMinutes(a as Dictionary) as Number {
        return hour(a) * 60 + minute(a);
    }

    // ── Daily runtime state ──────────────────────────────────────────────────
    // Per-day flags per alarm, reset automatically each calendar day:
    //   "f" => fired/dismissed already today
    //   "p" => plainFire (awake detected -> skip smart wake, fire on time)
    //   "s" => snooze count today
    //   "best" => best lightness seen so far in the window (for debugging)

    // Cheap day check: derives the day number from the cached midnight rather
    // than making a fresh Gregorian.info() call on every tick.
    static function resetIfNewDay() as Void {
        var ctx = dayContext(Time.now().value());
        var today = ctx[0] / 86400;                  // day index from midnight
        var stored = Application.Storage.getValue(KEY_STATE_DAY);
        if (stored == null || stored != today) {
            Application.Storage.setValue(KEY_STATE_DAY, today);
            Application.Storage.setValue(KEY_DAY_STATE, {});
            _dayStateCache = {};

            // Clear ringing/snooze state ONLY when it is genuinely stale.
            //
            // These two used to be wiped unconditionally, which quietly deleted
            // work in progress: snoozing at 23:58 for five minutes meant that at
            // 00:00 the pending snooze was erased and the alarm never rang again.
            // An oversleep is the single worst thing this app can do, and it
            // needed nothing more unusual than a late night to trigger.
            //
            // "Fired today" is genuinely day-scoped and is right to reset. A
            // pending snooze and an alarm that is ringing right now are absolute
            // moments in time, and they legitimately span midnight.
            var now = Time.now().value();
            var graceSecs = FIRE_GRACE_MINS * 60;

            var sn = Application.Storage.getValue(KEY_SNOOZE_UNTIL);
            if (sn == null || (sn as Number) + graceSecs < now) {
                Application.Storage.setValue(KEY_SNOOZE_UNTIL, null);
            }

            var rs = Application.Storage.getValue(KEY_RING_START);
            if (rs == null || (now - (rs as Number)) > graceSecs) {
                Application.Storage.setValue(KEY_RING_ID, null);
            }
        }
    }

    // Cached: hasFired() is called once per alarm per scan, and each call used to
    // deserialise this dictionary from storage.
    static function getDayState() as Dictionary {
        if (_dayStateCache != null) { return _dayStateCache as Dictionary; }
        var v = Application.Storage.getValue(KEY_DAY_STATE);
        _dayStateCache = (v == null) ? {} : (v as Dictionary);
        return _dayStateCache as Dictionary;
    }

    static function stateFor(alarmId as Number) as Dictionary {
        var all = getDayState();
        var key = alarmId.toString();
        var s = all.get(key);
        if (s == null) { return { "f" => false, "p" => false, "s" => 0 }; }
        return s as Dictionary;
    }

    static function setStateFor(alarmId as Number, s as Dictionary) as Void {
        var all = getDayState();
        all.put(alarmId.toString(), s);
        Application.Storage.setValue(KEY_DAY_STATE, all);
        _dayStateCache = all;
    }

    static function markFired(alarmId as Number) as Void {
        var s = stateFor(alarmId);
        s.put("f", true);
        setStateFor(alarmId, s);
    }

    // Arms a saved alarm for its NEXT genuine occurrence.
    //
    // Re-enabling a repeating alarm whose time already passed today used to make
    // it ring the instant you saved (the fired flag was cleared and the engine
    // saw it as due inside the grace window). So: clear the flags, but if today's
    // slot is already gone, mark it fired for today so it waits for tomorrow.
    static function armForNextOccurrence(a as Dictionary) as Void {
        var aid = id(a);
        clearFired(aid);
        clearStateFor(aid);
        if (!isOn(a)) { return; }

        var d = days(a);
        if (d == 0) { return; }   // one-time alarms use fireAt, already correct

        var now = Time.now();
        var info = Gregorian.info(now, Time.FORMAT_SHORT);
        var todayBit = 1 << (info.day_of_week - 1);
        if ((d & todayBit) == 0) { return; }   // not scheduled today anyway

        var midnight = now.value() - (info.hour * 3600 + info.min * 60 + info.sec);
        var target = midnight + totalMinutes(a) * 60;
        if (now.value() >= target) {
            markFired(aid);   // today's slot has passed - wait for the next day
        }
    }

    // Re-arm an alarm: clear today's fired/plain flags so it can fire again (used
    // when the user edits an alarm that had already gone off).
    static function clearFired(alarmId as Number) as Void {
        var s = stateFor(alarmId);
        s.put("f", false);
        s.put("p", false);
        setStateFor(alarmId, s);
    }

    static function markPlainFire(alarmId as Number) as Void {
        var s = stateFor(alarmId);
        s.put("p", true);
        setStateFor(alarmId, s);
    }

    static function hasFired(alarmId as Number) as Boolean {
        return _b(stateFor(alarmId), "f", false);
    }

    static function isPlainFire(alarmId as Number) as Boolean {
        return _b(stateFor(alarmId), "p", false);
    }

    static function snoozeCount(alarmId as Number) as Number {
        return _n(stateFor(alarmId), "s", 0);
    }

    static function incSnooze(alarmId as Number) as Void {
        var s = stateFor(alarmId);
        s.put("s", _n(s, "s", 0) + 1);
        setStateFor(alarmId, s);
    }

    // ── Ringing / snooze state ───────────────────────────────────────────────

    static function ringingId() as Number or Null {
        return Application.Storage.getValue(KEY_RING_ID);
    }

    static function setRinging(alarmId as Number or Null) as Void {
        Application.Storage.setValue(KEY_RING_ID, alarmId);
        if (alarmId != null) {
            Application.Storage.setValue(KEY_RING_START, Time.now().value());
        }
    }

    static function ringStart() as Number or Null {
        return Application.Storage.getValue(KEY_RING_START);
    }

    // Start ringing an alarm. One-time alarms are switched off immediately since
    // they've done their job.
    static function beginRing(alarmId as Number) as Void {
        setRinging(alarmId);
        var found = findById(alarmId);
        if (found[1] != null && days(found[1] as Dictionary) == 0) {
            disableById(alarmId);
        }
    }

    // A ring is "stale" if it was set more than the grace period ago. This happens
    // when the background fired the alarm but the watch couldn't surface the app
    // until much later. We drop stale rings so an old alarm never goes off hours
    // late (e.g. firing at 7:04 for a 5:54 alarm).
    static function clearStaleRing() as Void {
        var id = ringingId();
        if (id == null) { return; }
        var start = ringStart();
        if (start == null || (Time.now().value() - start) > FIRE_GRACE_MINS * 60) {
            if (id != null) { markFired(id); }
            setRinging(null);
        }
    }

    // Turn an alarm off by id (used to retire one-time alarms after they fire).
    static function disableById(alarmId as Number) as Void {
        var found = findById(alarmId);
        var idx = found[0] as Number;
        if (idx >= 0) {
            var a = found[1] as Dictionary;
            a.put("on", false);
            updateAlarm(idx, a);
        }
    }

    static function snoozeUntil() as Number or Null {
        return Application.Storage.getValue(KEY_SNOOZE_UNTIL);
    }

    static function setSnoozeUntil(epochSecs as Number or Null) as Void {
        Application.Storage.setValue(KEY_SNOOZE_UNTIL, epochSecs);
    }

    static function snoozedAlarmId() as Number or Null {
        return Application.Storage.getValue(KEY_SNOOZE_ID);
    }

    // Schedule a snoozed alarm to re-fire at a future epoch time.
    // Drops everything that only means something INSIDE one Active Alarm Mode
    // session: a pending snooze, and any ringing flag left behind.
    //
    // A snooze is a promise made within a sleep session ("wake me again in five
    // minutes"). Leaving Active Alarm Mode ends that session, so the promise
    // should end with it. Without this, snoozing a 12:00 alarm and then dropping
    // out of Active Alarm Mode - the palm gesture does exactly that - left the
    // snooze alive in storage. Re-entering at 12:04 showed "Next Alarm: None",
    // and then the alarm went off anyway at 12:05 announcing "2 snoozes left".
    //
    // The base schedule is untouched: an alarm set for 2 pm is still there when
    // you come back at 1:47, because that is a scheduled alarm, not a snooze.
    static function clearSessionState() as Void {
        Application.Storage.setValue(KEY_SNOOZE_UNTIL, null);
        Application.Storage.setValue(KEY_SNOOZE_ID, null);
        setRinging(null);
    }

    static function scheduleSnooze(alarmId as Number, epochSecs as Number) as Void {
        Application.Storage.setValue(KEY_SNOOZE_ID, alarmId);
        Application.Storage.setValue(KEY_SNOOZE_UNTIL, epochSecs);
    }

    // Find an alarm dict by id (or null). Returns [index, dict].
    static function findById(alarmId as Number) as Array {
        var list = getAlarms();
        for (var i = 0; i < list.size(); i++) {
            var a = list[i] as Dictionary;
            if (id(a) == alarmId) { return [i, a]; }
        }
        return [-1, null];
    }


    // Shallow copy of an alarm dict (all values are primitives). Used so the
    // editor can work on a copy and discard changes on cancel.
    static function clone(a as Dictionary) as Dictionary {
        var keys = a.keys();
        var out = {};
        for (var i = 0; i < keys.size(); i++) {
            var k = keys[i];
            out.put(k, a.get(k));
        }
        return out;
    }

    // ── Tiny typed helpers ───────────────────────────────────────────────────

    private static function _n(d as Dictionary, key as String, def as Number) as Number {
        var v = d.get(key);
        return (v != null) ? v as Number : def;
    }

    private static function _b(d as Dictionary, key as String, def as Boolean) as Boolean {
        var v = d.get(key);
        return (v != null) ? v as Boolean : def;
    }
}
