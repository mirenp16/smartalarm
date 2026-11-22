import Toybox.Test;
import Toybox.Lang;
import Toybox.Application;

(:test)
function rearmEarlyDismissedRepeatBeforeDeadline(logger as Test.Logger) as Boolean {
    var remaining=[22*60,60,1];
    for (var i=0;i<remaining.size();i++) {
    resetFixture();
    var now=utc(2026,11,22,5,38);
    var deadline=utc(2026,11,22,6,0);
    AlarmClock.setTestTime(now,0);
    var a=repeatAlarm(6,0,DAYS_ALL);
    walkingAt(now);
    var id=AlarmStore.id(a);
    Test.assert(AlarmEngine.evaluate(now) == id);
    AlarmStore.beginRing(id);
    AlarmStore.clearSessionState(); // dismiss and leave Active Alarm Mode
    now=deadline-remaining[i];
    AlarmClock.setTestTime(now,0);
    AlarmStore.invalidate(); // return from the main list with the alarm still ON
    AlarmStore.startActiveSession();
    AlarmStore.invalidate(); // rearmed deadline must persist across a restart
    AlarmStore.startActiveSession();
    Test.assert(AlarmStore.isOn(AlarmStore.findById(id)[1]));
    Test.assert(AlarmEngine.secsUntilNextTarget(now) == remaining[i]);
    for (var at=now;at<deadline;at+=15) {
        AlarmClock.setTestTime(at,0);
        walkingAt(at); // awake evidence must not immediately ring it again
        Test.assert(AlarmEngine.evaluate(at) == -1);
    }
    AlarmClock.setTestTime(deadline,0);
    Test.assert(AlarmEngine.evaluate(deadline) == id);
    AlarmStore.beginRing(id);
    AlarmStore.setRinging(null);
    Test.assert(AlarmEngine.evaluate(deadline+15) == -1);
    }
    return true;
}

(:test)
function activeRearmPreservesRingSnoozeAndPastOccurrences(logger as Test.Logger) as Boolean {
    resetFixture();
    var now=utc(2026,11,22,5,38);
    var deadline=utc(2026,11,22,6,0);
    AlarmClock.setTestTime(now,0);
    var a=repeatAlarm(6,0,DAYS_ALL);
    var id=AlarmStore.id(a);
    walkingAt(now);
    Test.assert(AlarmEngine.evaluate(now) == id);
    AlarmStore.beginRing(id);
    AlarmStore.startActiveSession();
    Test.assert(AlarmStore.ringingId() == id);
    Test.assert(AlarmStore.occurrenceDone(id,deadline));
    AlarmStore.setRinging(null);
    AlarmStore.incSnooze(id);
    AlarmStore.scheduleSnooze(id,now+300);
    AlarmStore.startActiveSession();
    Test.assert(AlarmStore.occurrenceDone(id,deadline));
    Test.assert(AlarmStore.snoozeCount(id) == 1);
    Test.assert(AlarmStore.snoozeUntil() == now+300);
    AlarmStore.clearSessionState();
    // Without reentry, an early dismissal must still suppress a second ring.
    Test.assert(AlarmEngine.evaluate(deadline) == -1);
    AlarmClock.setTestTime(deadline,0);
    AlarmStore.startActiveSession(); // at/after deadline means next day's repeat
    Test.assert(AlarmStore.occurrenceDone(id,deadline));
    Test.assert(AlarmStore.nextFireEpoch(a,deadline) == deadline+86400);
    return true;
}

(:test)
function activeRearmCrossesMidnightAndPreservesHistory(logger as Test.Logger) as Boolean {
    resetFixture();
    var now=utc(2026,11,22,23,50);
    var deadline=utc(2026,11,23,0,30);
    AlarmClock.setTestTime(now,0);
    var a=repeatAlarm(0,30,DAY_MON);
    var id=AlarmStore.id(a);
    AlarmStore.markOccurrence(id,deadline-7*86400);
    walkingAt(now);
    Test.assert(AlarmEngine.evaluate(now) == id);
    AlarmStore.beginRing(id);
    AlarmStore.clearSessionState();
    AlarmStore.startActiveSession();
    Test.assert(AlarmStore.occurrenceDone(id,deadline-7*86400));
    Test.assert(!AlarmStore.occurrenceDone(id,deadline));
    Test.assert(AlarmEngine.evaluate(now) == -1);
    AlarmClock.setTestTime(deadline,0);
    Test.assert(AlarmEngine.evaluate(deadline) == id);
    AlarmStore.beginRing(id);
    AlarmStore.setRinging(null);
    Test.assert(!AlarmStore.deadlineOnly(id,deadline));
    Test.assert(AlarmEngine.evaluate(deadline+15) == -1);
    Test.assert(AlarmStore.nextFireEpoch(a,deadline+15) == deadline+7*86400);
    return true;
}

(:test)
function activeRearmLeavesDisabledAndFreshAlarmsAlone(logger as Test.Logger) as Boolean {
    resetFixture();
    var now=utc(2026,11,22,5,38);
    var deadline=utc(2026,11,22,6,0);
    AlarmClock.setTestTime(now,0);
    var disabled=repeatAlarm(6,0,DAYS_ALL);
    AlarmStore.markOccurrence(AlarmStore.id(disabled),deadline);
    AlarmStore.disableById(AlarmStore.id(disabled));
    var once=AlarmStore.newAlarm();
    AlarmStore.addAlarm(once);
    AlarmStore.markOccurrence(AlarmStore.id(once),deadline);
    AlarmStore.disableById(AlarmStore.id(once));
    var fresh=repeatAlarm(6,0,DAYS_ALL);
    AlarmStore.startActiveSession();
    Test.assert(AlarmStore.occurrenceDone(AlarmStore.id(disabled),deadline));
    Test.assert(!AlarmStore.isOn(disabled));
    Test.assert(!AlarmStore.isOn(once));
    walkingAt(now);
    // A fresh alarm must retain its normal sleep-window functionality.
    Test.assert(AlarmEngine.evaluate(now) == AlarmStore.id(fresh));
    return true;
}

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
