import Toybox.Test;
import Toybox.Lang;
import Toybox.Application;

(:test)
function activeReentryPreservesOneTimeSnooze(logger as Test.Logger) as Boolean {
    resetFixture();
    var now=utc(2026,10,1,6,0);
    AlarmClock.setTestTime(now,0);
    var a=AlarmStore.newAlarm();
    a.put("fireAt",now);
    AlarmStore.addAlarm(a);
    var id=AlarmStore.id(a);
    Test.assert(AlarmEngine.evaluate(now) == id);
    AlarmStore.beginRing(id);
    AlarmStore.incSnooze(id);
    AlarmStore.scheduleSnooze(id,now+300);
    AlarmStore.setRinging(null);
    AlarmStore.invalidate();
    AlarmClock.setTestTime(now+60,0);
    AlarmStore.startActiveSession();
    Test.assert(!AlarmStore.isOn(AlarmStore.findById(id)[1]));
    Test.assert(AlarmStore.validSnoozeId() == id);
    Test.assert(AlarmStore.snoozeCount(id) == 1);
    Test.assert(AlarmEngine.evaluate(now+60) == -1);
    AlarmClock.setTestTime(now+300,0);
    Test.assert(AlarmEngine.evaluate(now+300) == id);
    AlarmStore.beginRing(id);
    Test.assert(AlarmStore.snoozeCount(id) == 1);
    return true;
}

(:test)
function activeReentryRejectsOldOrInvalidRinging(logger as Test.Logger) as Boolean {
    resetFixture();
    var now=utc(2026,10,1,6,0);
    AlarmClock.setTestTime(now,0);
    var a=repeatAlarm(6,0,DAYS_ALL);
    var id=AlarmStore.id(a);
    AlarmStore.setRinging(id);
    AlarmStore.startActiveSession();
    Test.assert(AlarmStore.ringingId() == id);
    AlarmStore.scheduleSnooze(id,now-901);
    Application.Storage.setValue(KEY_RING_START,now-901);
    AlarmStore.startActiveSession();
    Test.assert(AlarmStore.ringingId() == null && AlarmStore.validSnoozeId() == null);
    AlarmStore.setRinging(id);
    Application.Storage.setValue(KEY_RING_START,now+1);
    AlarmStore.startActiveSession();
    Test.assert(AlarmStore.ringingId() == null);
    AlarmStore.setRinging(9999);
    AlarmStore.startActiveSession();
    Test.assert(AlarmStore.ringingId() == null);
    AlarmStore.scheduleSnooze(id,now+300);
    AlarmStore.clearSessionState();
    Test.assert(AlarmStore.validSnoozeId() == null);
    return true;
}

(:test)
function rearmAfterMidnightDoesNotCatchUpYesterday(logger as Test.Logger) as Boolean {
    resetFixture();
    var now=utc(2026,10,1,0,2);
    AlarmClock.setTestTime(now,0);
    var a=repeatAlarm(23,55,DAYS_ALL);
    AlarmStore.armForNextOccurrence(a,true);
    Test.assert(AlarmEngine.evaluate(now) == -1);
    Test.assert(AlarmStore.nextFireEpoch(a,now) == utc(2026,10,1,23,55));
    // An unchanged, already-enabled alarm must retain its catch-up grace.
    var b=repeatAlarm(23,56,DAYS_ALL);
    AlarmStore.armForNextOccurrence(b,false);
    Test.assert(AlarmEngine.evaluate(now) == AlarmStore.id(b));
    return true;
}

(:test)
function noSensorDeadlineAcrossEveryWindow(logger as Test.Logger) as Boolean {
    for (var i=0;i<WINDOW_OPTIONS.size();i++) {
        resetFixture();
        var deadline=utc(2026,10,1,6,0);
        var start=deadline-WINDOW_OPTIONS[i]*60;
        AlarmClock.setTestTime(start,0);
        var a=repeatAlarm(6,0,DAYS_ALL);
        a.put("win",WINDOW_OPTIONS[i]);
        for (var at=start;at<=deadline;at+=15) {
            AlarmClock.setTestTime(at,0);
            SleepDetector.recordHr(null,at);
            Test.assert(AlarmEngine.evaluate(at) == (at < deadline ? -1 : AlarmStore.id(a)));
        }
        AlarmStore.beginRing(AlarmStore.id(a));
        AlarmStore.setRinging(null);
        Test.assert(AlarmEngine.evaluate(deadline+15) == -1);
    }
    return true;
}
