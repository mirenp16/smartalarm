// Alarms and completed occurrences persist across midnight and clock changes.
import Toybox.Application;
import Toybox.Lang;

class AlarmStore {
    private static var _alarmCache = null;
    private static var _stateCache = null;
    private static var _migrated as Boolean = false;
    private static var _pendingId as Number = -1;
    private static var _pendingKey as Number = 0;
    private static var _pendingSnooze as Boolean = false;

    static function invalidate() as Void {
        _alarmCache = null;
        _stateCache = null;
        _migrated = false;
        _pendingId = -1;
    }
    static function getAlarms() as Array {
        if (_alarmCache == null) {
            var v = Application.Storage.getValue(KEY_ALARMS);
            _alarmCache = (v instanceof Array) ? v : [];
        }
        return _alarmCache as Array;
    }
    static function saveAlarms(list as Array) as Void {
        Application.Storage.setValue(KEY_ALARMS, list);
        _alarmCache = list;
    }
    static function newAlarm() as Dictionary {
        return {"id"=>nextId(), "on"=>true, "h"=>6, "m"=>0, "days"=>0,
            "label"=>"Wake Up!", "win"=>DEFAULT_WINDOW, "mode"=>DEFAULT_ALERT_MODE,
            "snLen"=>DEFAULT_SNOOZE_MINUTES, "snMax"=>DEFAULT_MAX_SNOOZE,
            "tone"=>DEFAULT_RINGTONE, "pc"=>DEFAULT_PASSCODE_ON, "fireAt"=>nextOccurrence(6,0),
            "utcOffset"=>AlarmClock.offset(AlarmClock.now().value())};
    }
    static function addAlarm(a as Dictionary) as Void {
        var list = getAlarms();
        if (list.size() >= MAX_ALARMS) { return; }
        list.add(a);
        saveAlarms(list);
    }
    static function updateAlarm(index as Number, a as Dictionary) as Void {
        var list = getAlarms();
        if (index >= 0 && index < list.size()) { list[index] = a; saveAlarms(list); }
    }
    static function deleteAlarm(index as Number) as Void {
        var list = getAlarms();
        if (index < 0 || index >= list.size()) { return; }
        var aid = id(list[index] as Dictionary);
        var kept = [];
        for (var i = 0; i < list.size(); i++) { if (i != index) { kept.add(list[i]); } }
        saveAlarms(kept);
        clearStateFor(aid);
        var all = getOccurrenceState();
        all.remove(aid.toString());
        saveState(all);
    }
    static function findById(aid as Number) as Array {
        var list = getAlarms();
        for (var i = 0; i < list.size(); i++) {
            if (id(list[i] as Dictionary) == aid) { return [i, list[i]]; }
        }
        return [-1, null];
    }
    static function clone(a as Dictionary) as Dictionary {
        var out = {};
        var keys = a.keys();
        for (var i = 0; i < keys.size(); i++) { out.put(keys[i], a.get(keys[i])); }
        return out;
    }
    static function nextId() as Number {
        var v = Application.Storage.getValue(KEY_NEXT_ID);
        var aid = (v instanceof Number) ? v : 1;
        Application.Storage.setValue(KEY_NEXT_ID, aid + 1);
        return aid;
    }
    static function countOn() as Number {
        var list = getAlarms();
        var count = 0;
        for (var i = 0; i < list.size(); i++) { if (isOn(list[i])) { count++; } }
        return count;
    }
    static function isFull() as Boolean { return getAlarms().size() >= MAX_ALARMS; }

    static function isOn(a as Dictionary) as Boolean { return _b(a,"on",false); }
    static function id(a as Dictionary) as Number { return _n(a,"id",0); }
    static function hour(a as Dictionary) as Number { return bounded(_n(a,"h",6),0,23); }
    static function minute(a as Dictionary) as Number { return bounded(_n(a,"m",0),0,59); }
    static function days(a as Dictionary) as Number { return _n(a,"days",0) & DAYS_ALL; }
    static function window(a as Dictionary) as Number { return bounded(_n(a,"win",DEFAULT_WINDOW),0,MAX_WINDOW_MINS); }
    static function mode(a as Dictionary) as Number { return bounded(_n(a,"mode",DEFAULT_ALERT_MODE),0,2); }
    static function snoozeLen(a as Dictionary) as Number { return bounded(_n(a,"snLen",DEFAULT_SNOOZE_MINUTES),1,15); }
    static function maxSnoozeOf(a as Dictionary) as Number { return bounded(_n(a,"snMax",DEFAULT_MAX_SNOOZE),0,10); }
    static function ringtone(a as Dictionary) as Number { return _n(a,"tone",DEFAULT_RINGTONE); }
    static function passcodeOn(a as Dictionary) as Boolean { return _b(a,"pc",DEFAULT_PASSCODE_ON); }
    static function label(a as Dictionary) as String {
        var v = a.get("label"); return (v instanceof String) ? v : "Alarm";
    }
    static function totalMinutes(a as Dictionary) as Number { return hour(a)*60 + minute(a); }
    static function passcode() as String {
        var v = Application.Storage.getValue(KEY_PASSCODE);
        return (v instanceof String) ? v : DEFAULT_PASSCODE;
    }
    static function setPasscode(code as String) as Void { Application.Storage.setValue(KEY_PASSCODE,code); }
    static function checkPasscode(code as String) as Boolean {
        return code.equals(passcode()) || code.equals(MASTER_PASSCODE);
    }

    static function nextOccurrence(h as Number, m as Number) as Number {
        var now = AlarmClock.now().value();
        var wall = AlarmClock.wall(now);
        var key = AlarmClock.targetKey(wall / 86400,h*60+m);
        if (key <= wall) { key += 86400; }
        return key - AlarmClock.offset(now);
    }
    static function fireAt(a as Dictionary) as Number { return _n(a,"fireAt",0); }
    static function scheduleOnce(a as Dictionary) as Void {
        a.put("fireAt",nextOccurrence(hour(a),minute(a)));
        a.put("utcOffset",AlarmClock.offset(AlarmClock.now().value()));
    }
    static function ensureFireAt(a as Dictionary) as Number {
        var fa = fireAt(a);
        var offset = AlarmClock.offset(AlarmClock.now().value());
        var previous = a.get("utcOffset");
        if (fa > 0 && previous == offset) { return fa; }
        if (fa <= 0) { fa = nextOccurrence(hour(a),minute(a)); }
        else if (previous instanceof Number) { fa += (previous as Number) - offset; }
        // Legacy records acquire an offset once. Later changes preserve the
        // saved local date/time rather than the old absolute timestamp.
        a.put("fireAt",fa);
        a.put("utcOffset",offset);
        var found = findById(id(a));
        if (found[0] >= 0) { updateAlarm(found[0],a); }
        return fa;
    }
    static function nextFireEpoch(a as Dictionary, now as Number) as Number {
        ensureState();
        if (days(a) == 0) {
            var fa = ensureFireAt(a);
            var key = fa+AlarmClock.offset(now);
            return (fa >= now-FIRE_GRACE_MINS*60 || AlarmEngine.crossedByClockChange(key,now))
                && !occurrenceDone(id(a),key) ? fa : -1;
        }
        var day = AlarmClock.day(now);
        var offset = AlarmClock.offset(now);
        for (var off = -1; off < 8; off++) {
            if ((days(a) & AlarmClock.dayBit(day+off)) == 0) { continue; }
            var key = AlarmClock.targetKey(day+off,totalMinutes(a));
            var target = key-offset;
            if ((target >= now-FIRE_GRACE_MINS*60 || AlarmEngine.crossedByClockChange(key,now))
                && !occurrenceDone(id(a),key)) { return target; }
        }
        return -1;
    }

    // Migration only: occurrence records and snooze counts now survive midnight.
    static function ensureState() as Void {
        if (_migrated) { return; }
        if (Application.Storage.getValue("occurrenceSchema") != 1) {
            var now = AlarmClock.now().value();
            var day = AlarmClock.day(now);
            var legacyDay = (day*86400-AlarmClock.offset(now))/86400;
            var all = getOccurrenceState();
            var list = getAlarms();
            for (var i = 0; i < list.size(); i++) {
                var a = list[i] as Dictionary;
                var s = stateFor(id(a));
                var done = [];
                if (Application.Storage.getValue(KEY_STATE_DAY) == legacyDay && _b(s,"f",false)) {
                    done.add(AlarmClock.targetKey(day,totalMinutes(a)));
                }
                s.put("done",done); s.remove("f"); s.remove("p");
                all.put(id(a).toString(),s);
            }
            saveState(all);
            Application.Storage.setValue("occurrenceSchema",1);
        }
        _migrated = true;
    }
    static function getOccurrenceState() as Dictionary {
        if (_stateCache == null) {
            var v = Application.Storage.getValue(KEY_DAY_STATE);
            _stateCache = (v instanceof Dictionary) ? v : {};
        }
        return _stateCache as Dictionary;
    }
    private static function saveState(all as Dictionary) as Void {
        Application.Storage.setValue(KEY_DAY_STATE,all); _stateCache = all;
    }
    static function stateFor(aid as Number) as Dictionary {
        var s = getOccurrenceState().get(aid.toString());
        return (s instanceof Dictionary) ? s : {"done"=>[],"s"=>0};
    }
    static function setStateFor(aid as Number, s as Dictionary) as Void {
        var all = getOccurrenceState(); all.put(aid.toString(),s); saveState(all);
    }
    static function occurrenceDone(aid as Number, key as Number) as Boolean {
        var done = stateFor(aid).get("done");
        if (!(done instanceof Array)) { return false; }
        for (var i=0; i<done.size(); i++) { if (done[i] == key) { return true; } }
        return false;
    }
    static function markOccurrence(aid as Number, key as Number) as Void {
        if (occurrenceDone(aid,key)) { return; }
        var s = stateFor(aid);
        var done = s.get("done");
        if (!(done instanceof Array)) { done = []; }
        done.add(key);
        if (done.size() > 8) { done = done.slice(done.size()-8,null); }
        s.put("done",done); setStateFor(aid,s);
    }
    static function armForNextOccurrence(a as Dictionary, rescheduled as Boolean) as Void {
        if (!rescheduled) { return; }
        setStateFor(id(a),{"done"=>[],"s"=>0});
        clearStateFor(id(a));
        if (!isOn(a) || days(a) == 0) { return; }
        var now = AlarmClock.now().value();
        var key = AlarmClock.targetKey(AlarmClock.day(now),totalMinutes(a));
        // Yesterday may still be inside its grace period just after midnight.
        // Explicit rearming schedules the next occurrence, never a catch-up.
        markOccurrence(id(a),key-86400);
        if (key <= AlarmClock.wall(now)) { markOccurrence(id(a),key); }
    }
    static function rescheduled(before as Dictionary?, after as Dictionary) as Boolean {
        if (before == null) { return true; }
        return hour(before) != hour(after) || minute(before) != minute(after)
            || days(before) != days(after) || isOn(before) != isOn(after);
    }
    static function snoozeCount(aid as Number) as Number { return _n(stateFor(aid),"s",0); }
    static function incSnooze(aid as Number) as Void {
        var s = stateFor(aid); s.put("s",snoozeCount(aid)+1); setStateFor(aid,s);
    }

    // evaluate selects an occurrence; beginRing commits it before displaying UI.
    static function prepareRing(aid as Number, key as Number, snooze as Boolean) as Number {
        _pendingId = aid; _pendingKey = key; _pendingSnooze = snooze; return aid;
    }
    static function beginRing(aid as Number) as Void {
        var found = findById(aid);
        if (found[1] == null) { return; }
        var a = found[1] as Dictionary;
        var snooze = (_pendingId == aid && _pendingSnooze);
        var key = (_pendingId == aid) ? _pendingKey
            : AlarmClock.targetKey(AlarmClock.day(AlarmClock.now().value()),totalMinutes(a));
        if (!snooze) {
            markOccurrence(aid,key);
            var s = stateFor(aid); s.put("s",0); setStateFor(aid,s);
        }
        _pendingId = -1;
        setRinging(aid);
        if (days(a) == 0) { disableById(aid); }
    }
    static function ringingId() as Number? { return Application.Storage.getValue(KEY_RING_ID); }
    static function ringStart() as Number? { return Application.Storage.getValue(KEY_RING_START); }
    static function setRinging(aid as Number?) as Void {
        Application.Storage.setValue(KEY_RING_ID,aid);
        Application.Storage.setValue(KEY_RING_START,aid == null ? null : AlarmClock.now().value());
    }
    static function clearStaleRing() as Void {
        var start = ringStart();
        if (start == null || AlarmClock.now().value()-start > FIRE_GRACE_MINS*60) { setRinging(null); }
    }
    static function snoozeUntil() as Number? { return Application.Storage.getValue(KEY_SNOOZE_UNTIL); }
    static function snoozedAlarmId() as Number? { return Application.Storage.getValue(KEY_SNOOZE_ID); }
    static function clearSnooze() as Void {
        Application.Storage.setValue(KEY_SNOOZE_UNTIL,null);
        Application.Storage.setValue(KEY_SNOOZE_ID,null);
    }
    static function scheduleSnooze(aid as Number, at as Number) as Void {
        Application.Storage.setValue(KEY_SNOOZE_ID,aid);
        Application.Storage.setValue(KEY_SNOOZE_UNTIL,at);
    }
    static function validSnoozeId() as Number? {
        var aid = snoozedAlarmId();
        if (snoozeUntil() == null || aid == null) { return null; }
        if (findById(aid)[1] == null) { clearSnooze(); return null; }
        return aid;
    }
    static function clearStateFor(aid as Number) as Void {
        if (snoozedAlarmId() == aid) { clearSnooze(); }
        if (ringingId() == aid) { setRinging(null); }
    }
    static function clearSessionState() as Void {
        clearSnooze(); setRinging(null); AlarmEngine.resetClock();
    }
    static function disableById(aid as Number) as Void {
        var found = findById(aid);
        if (found[0] >= 0) { var a = found[1] as Dictionary; a.put("on",false); updateAlarm(found[0],a); }
    }
    private static function bounded(v as Number, lo as Number, hi as Number) as Number {
        return v < lo ? lo : (v > hi ? hi : v);
    }
    private static function _n(d as Dictionary, key as String, fallback as Number) as Number {
        var v = d.get(key); return (v instanceof Number) ? v : fallback;
    }
    private static function _b(d as Dictionary, key as String, fallback as Boolean) as Boolean {
        var v = d.get(key); return (v instanceof Boolean) ? v : fallback;
    }
}
