// AlarmStore.mc
// The data layer. Manages the list of alarms plus per-day runtime state and the
// "currently ringing" state. Everything is persisted with Application.Storage so
// it survives app restarts and is readable from the background service.
//
// An alarm is stored as a Dictionary with short keys to save space:
//   "id"    Number   unique id
//   "on"    Boolean  enabled?
//   "h"     Number   hour (0-23)
//   "m"     Number   minute (0-59)
//   "days"  Number   day bitmask (see Constants.mc)
//   "label" String   user-facing label
//   "type"  Number   TYPE_SLEEP or TYPE_REMINDER
//   "win"   Number   wake-window minutes (sleep alarms only)
//   "mode"  Number   MODE_BOTH / MODE_SOUND / MODE_VIBE
//
// This whole class is annotated (:background) so the service can read/write it.

import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:background)
class AlarmStore {

    // ── Alarm list CRUD ──────────────────────────────────────────────────────

    static function getAlarms() as Array {
        var v = Application.Storage.getValue(KEY_ALARMS);
        if (v == null) { return []; }
        return v as Array;
    }

    static function saveAlarms(list as Array) as Void {
        Application.Storage.setValue(KEY_ALARMS, list);
    }

    // Builds a brand-new alarm Dictionary with sensible defaults.
    // Default days = 0 means "one-time" (fires once at the next 7:30, then off).
    static function newAlarm() as Dictionary {
        return {
            "id"     => nextId(),
            "on"     => true,
            "h"      => 7,
            "m"      => 30,
            "days"   => 0,
            "label"  => "Wake up",
            "type"   => TYPE_SLEEP,
            "win"    => 30,
            "mode"   => MODE_BOTH,
            "fireAt" => nextOccurrence(7, 30)
        };
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
            list.remove(list[index]);
            saveAlarms(list);
        }
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
    static function type(a as Dictionary)    as Number  { return _n(a, "type", TYPE_SLEEP); }
    static function window(a as Dictionary)  as Number  { return _n(a, "win", 30); }
    static function mode(a as Dictionary)    as Number  { return _n(a, "mode", MODE_BOTH); }
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

    static function resetIfNewDay() as Void {
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT).day;
        var stored = Application.Storage.getValue(KEY_STATE_DAY);
        if (stored == null || stored != today) {
            Application.Storage.setValue(KEY_STATE_DAY, today);
            Application.Storage.setValue(KEY_DAY_STATE, {});
            // A fresh day also clears any stale ringing/snooze state.
            Application.Storage.setValue(KEY_RING_ID, null);
            Application.Storage.setValue(KEY_SNOOZE_UNTIL, null);
        }
    }

    static function getDayState() as Dictionary {
        var v = Application.Storage.getValue(KEY_DAY_STATE);
        if (v == null) { return {}; }
        return v as Dictionary;
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
    }

    static function markFired(alarmId as Number) as Void {
        var s = stateFor(alarmId);
        s.put("f", true);
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

    // ── Config: snooze length + max ──────────────────────────────────────────

    static function snoozeMinutes() as Number {
        var v = Application.Storage.getValue(KEY_SNOOZE_MINS);
        return (v != null) ? v : DEFAULT_SNOOZE_MINUTES;
    }

    static function maxSnooze() as Number {
        var v = Application.Storage.getValue(KEY_MAX_SNOOZE);
        return (v != null) ? v : DEFAULT_MAX_SNOOZE;
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
