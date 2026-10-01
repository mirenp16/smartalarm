import Toybox.Test;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Application;

(:test)
function nextDisplayIncludesEarlierBackupBeforeSnooze(logger as Test.Logger) as Boolean {
    resetFixture();
    var now=utc(2026,10,1,6,0);
    AlarmClock.setTestTime(now,0);
    var a=repeatAlarm(6,0,DAYS_ALL);
    Test.assert(AlarmEngine.evaluate(now) == AlarmStore.id(a));
    AlarmStore.beginRing(AlarmStore.id(a));
    AlarmStore.setRinging(null);
    AlarmStore.scheduleSnooze(AlarmStore.id(a),now+600);
    repeatAlarm(6,2,DAYS_ALL);
    var view=new BedsideView();
    Test.assert(view.nextAlarmStr().equals("6:02 AM"));
    Test.assert(view.durationStr().equals("Duration: 00:02"));
    return true;
}

(:testSupport)
function utc(y as Number, mo as Number, d as Number, h as Number, m as Number) as Number {
    return Gregorian.moment({:year=>y,:month=>mo,:day=>d,:hour=>h,:minute=>m,:second=>0}).value();
}
(:testSupport)
function repeatAlarm(h as Number, m as Number, mask as Number) as Dictionary {
    var a = AlarmStore.newAlarm();
    a.put("h",h); a.put("m",m); a.put("days",mask);
    AlarmStore.addAlarm(a);
    return a;
}
(:testSupport)
function walkingAt(at as Number) as Void {
    SleepDetector.recordSteps(0,at-30);
    SleepDetector.recordSteps(12,at);
}

(:test)
function midnightWindowUsesTargetsWeekday(logger as Test.Logger) as Boolean {
    resetFixture();
    var now = utc(2026,9,30,23,45); // Wednesday; Thursday alarm
    AlarmClock.setTestTime(now,0);
    var a = repeatAlarm(0,30,DAY_THU);
    walkingAt(now);
    Test.assert(AlarmEngine.evaluate(now-1) == -1);
    Test.assert(AlarmEngine.evaluate(now) == AlarmStore.id(a));
    AlarmStore.beginRing(AlarmStore.id(a));
    AlarmStore.setRinging(null);
    AlarmClock.setTestTime(now+2700,0);
    AlarmStore.invalidate(); // state must survive restart AND midnight
    Test.assert(AlarmEngine.evaluate(now+2700) == -1);
    Test.assert(AlarmStore.nextFireEpoch(a,now+2700) == utc(2026,10,8,0,30));
    return true;
}

(:test)
function midnightDeadlineAndPreviousDayGrace(logger as Test.Logger) as Boolean {
    resetFixture();
    var now = utc(2026,10,1,0,0);
    AlarmClock.setTestTime(now,0);
    var a = repeatAlarm(0,0,DAYS_ALL);
    Test.assert(AlarmEngine.evaluate(now) == AlarmStore.id(a));
    AlarmStore.beginRing(AlarmStore.id(a));
    AlarmStore.setRinging(null);
    var b = repeatAlarm(23,55,DAY_WED);
    Test.assert(AlarmEngine.evaluate(now) == AlarmStore.id(b));
    AlarmStore.beginRing(AlarmStore.id(b));
    AlarmStore.setRinging(null);
    Test.assert(AlarmEngine.evaluate(now) == -1);
    return true;
}

(:test)
function snoozeCountSurvivesMidnight(logger as Test.Logger) as Boolean {
    resetFixture();
    var now = utc(2026,9,30,23,58);
    AlarmClock.setTestTime(now,0);
    var a = repeatAlarm(23,58,DAYS_ALL);
    var id = AlarmStore.id(a);
    Test.assert(AlarmEngine.evaluate(now) == id);
    AlarmStore.beginRing(id);
    AlarmStore.incSnooze(id);
    AlarmStore.incSnooze(id);
    AlarmStore.scheduleSnooze(id,now+300);
    AlarmStore.setRinging(null);
    AlarmClock.setTestTime(now+300,0);
    AlarmStore.invalidate();
    Test.assert(AlarmEngine.evaluate(now+300) == id);
    AlarmStore.beginRing(id);
    Test.assert(AlarmStore.snoozeCount(id) == 2);
    AlarmStore.setRinging(null);
    Test.assert(AlarmEngine.evaluate(now+315) == -1);
    Test.assert(AlarmStore.nextFireEpoch(a,now+315) == now+86400);
    return true;
}

(:test)
function springForwardPreservesSixAm(logger as Test.Logger) as Boolean {
    resetFixture();
    var before = utc(2026,3,8,6,59); // 01:59 EST
    AlarmClock.setTestTime(before,-18000);
    var repeated = repeatAlarm(6,0,DAYS_ALL);
    var once = AlarmStore.newAlarm();
    AlarmStore.addAlarm(once);
    Test.assert(AlarmStore.ensureFireAt(once) == utc(2026,3,8,11,0));
    Test.assert(AlarmEngine.evaluate(before) == -1);
    AlarmClock.setTestTime(before+60,-14400); // 03:00 EDT
    Test.assert(AlarmStore.nextFireEpoch(repeated,before+60) == utc(2026,3,8,10,0));
    Test.assert(AlarmStore.ensureFireAt(once) == utc(2026,3,8,10,0));
    return true;
}

(:test)
function skippedSpringTimeRingsImmediately(logger as Test.Logger) as Boolean {
    resetFixture();
    var before = utc(2026,3,8,6,59);
    AlarmClock.setTestTime(before,-18000);
    var a = repeatAlarm(2,30,DAYS_ALL);
    Test.assert(AlarmEngine.evaluate(before) == -1);
    AlarmClock.setTestTime(before+60,-14400);
    Test.assert(AlarmEngine.evaluate(before+60) == AlarmStore.id(a));
    AlarmStore.beginRing(AlarmStore.id(a));
    AlarmStore.setRinging(null);
    Test.assert(AlarmEngine.evaluate(before+75) == -1);
    return true;
}

(:test)
function fallBackDoesNotRepeatAlarm(logger as Test.Logger) as Boolean {
    resetFixture();
    var first = utc(2026,11,1,5,30); // first 01:30, EDT
    AlarmClock.setTestTime(first,-14400);
    var a = repeatAlarm(1,30,DAYS_ALL);
    Test.assert(AlarmEngine.evaluate(first) == AlarmStore.id(a));
    AlarmStore.beginRing(AlarmStore.id(a));
    AlarmStore.setRinging(null);
    AlarmClock.setTestTime(first+3600,-18000); // second 01:30, EST
    AlarmStore.invalidate();
    Test.assert(AlarmEngine.evaluate(first+3600) == -1);
    Test.assert(AlarmStore.nextFireEpoch(a,first+3600) == utc(2026,11,2,6,30));
    return true;
}

(:test)
function timezoneChangeKeepsLocalTimeAndSnoozeDuration(logger as Test.Logger) as Boolean {
    resetFixture();
    var now = utc(2026,9,30,4,0);
    AlarmClock.setTestTime(now,0);
    var a = AlarmStore.newAlarm();
    AlarmStore.addAlarm(a);
    var id = AlarmStore.id(a);
    AlarmStore.scheduleSnooze(id,now+300);
    AlarmClock.setTestTime(now+60,3600);
    Test.assert(AlarmStore.ensureFireAt(a) == utc(2026,9,30,5,0));
    Test.assert(AlarmStore.snoozeUntil() == now+300);
    AlarmClock.setTestTime(now+120,-3600);
    Test.assert(AlarmStore.ensureFireAt(a) == utc(2026,9,30,7,0));
    return true;
}

(:test)
function legacyFiredStateMigrates(logger as Test.Logger) as Boolean {
    resetFixture();
    var now = utc(2026,9,30,5,45);
    AlarmClock.setTestTime(now,0);
    var a = repeatAlarm(6,0,DAYS_ALL);
    Application.Storage.setValue("occurrenceSchema",null);
    Application.Storage.setValue(KEY_STATE_DAY,now/86400);
    AlarmStore.setStateFor(AlarmStore.id(a),{"f"=>true,"s"=>2});
    AlarmStore.invalidate();
    walkingAt(now);
    Test.assert(AlarmEngine.evaluate(now) == -1);
    Test.assert(AlarmStore.nextFireEpoch(a,now) == utc(2026,10,1,6,0));
    return true;
}

(:test)
function earliestDeadlineWinsOverListOrder(logger as Test.Logger) as Boolean {
    resetFixture();
    var now = utc(2026,9,30,6,0);
    AlarmClock.setTestTime(now,0);
    repeatAlarm(6,30,DAYS_ALL);
    var due = repeatAlarm(6,0,DAYS_ALL);
    walkingAt(now);
    Test.assert(AlarmEngine.evaluate(now) == AlarmStore.id(due));
    return true;
}

(:test)
function cosmeticEditPreservesEarlyOccurrence(logger as Test.Logger) as Boolean {
    resetFixture();
    var now = utc(2026,9,30,23,45);
    AlarmClock.setTestTime(now,0);
    var a = repeatAlarm(0,30,DAYS_ALL);
    walkingAt(now);
    Test.assert(AlarmEngine.evaluate(now) == AlarmStore.id(a));
    AlarmStore.beginRing(AlarmStore.id(a));
    AlarmStore.setRinging(null);
    var copy = AlarmStore.clone(a);
    copy.put("label","Gym");
    AlarmStore.armForNextOccurrence(copy,AlarmStore.rescheduled(a,copy));
    Test.assert(AlarmEngine.evaluate(now) == -1);
    return true;
}

(:test)
function reportedMorningTimeline(logger as Test.Logger) as Boolean {
    resetFixture();
    var start = utc(2026,9,24,4,15);
    AlarmClock.setTestTime(start,0);
    var a = repeatAlarm(6,0,DAYS_ALL);
    var window = utc(2026,9,24,5,15);
    var woke = utc(2026,9,24,4,36);
    for (var at=start; at<=window; at+=15) {
        AlarmClock.setTestTime(at,0);
        SleepDetector.recordHr(at < woke ? 50 : 75,at);
        Test.assert(AlarmEngine.evaluate(at) == (at < window ? -1 : AlarmStore.id(a)));
    }
    return true;
}

(:test)
function shortSensorGapBreaksAwakeStreak(logger as Test.Logger) as Boolean {
    resetFixture();
    var at = utc(2026,9,30,5,0);
    AlarmClock.setTestTime(at,0);
    for (var i=0;i<80;i++) { SleepDetector.recordHr(50,at); }
    for (var i=0;i<20;i++) { SleepDetector.recordHr(75,at); }
    Test.assert(SleepDetector.isAwake());
    AlarmClock.setTestTime(at+60,0);
    Test.assert(!SleepDetector.isAwake());
    SleepDetector.recordHr(75,at+60);
    Test.assert(!SleepDetector.isAwake());
    Test.assert(SleepDetector.ready()); // brief interruption keeps the baseline
    return true;
}

(:test)
function skippedAlarmsRemainPendingDuringGrace(logger as Test.Logger) as Boolean {
    resetFixture();
    var before=utc(2026,3,8,6,59);
    AlarmClock.setTestTime(before,-18000);
    var first=repeatAlarm(2,0,DAYS_ALL);
    var second=repeatAlarm(2,30,DAYS_ALL);
    Test.assert(AlarmEngine.evaluate(before) == -1);
    AlarmClock.setTestTime(before+60,-14400);
    Test.assert(AlarmEngine.evaluate(before+60) == AlarmStore.id(first));
    AlarmStore.beginRing(AlarmStore.id(first));
    AlarmStore.setRinging(null);
    AlarmClock.setTestTime(before+120,-14400);
    Test.assert(AlarmEngine.secsUntilNextTarget(before+120) == 0);
    Test.assert(AlarmStore.id(AlarmEngine.nextAlarm(before+120)) == AlarmStore.id(second));
    Test.assert(AlarmEngine.evaluate(before+120) == AlarmStore.id(second));
    return true;
}

(:test)
function overdueBackupKeepsActiveMode(logger as Test.Logger) as Boolean {
    resetFixture();
    var at=utc(2026,9,30,6,0);
    AlarmClock.setTestTime(at,0);
    var first=repeatAlarm(6,0,DAYS_ALL);
    var backup=repeatAlarm(6,1,DAYS_ALL);
    Test.assert(AlarmEngine.evaluate(at) == AlarmStore.id(first));
    AlarmStore.beginRing(AlarmStore.id(first));
    AlarmStore.setRinging(null);
    AlarmClock.setTestTime(at+120,0);
    Test.assert(AlarmEngine.secsUntilNextTarget(at+120) == 0);
    Test.assert(AlarmEngine.evaluate(at+120) == AlarmStore.id(backup));
    return true;
}

(:test)
function fullCapacityScheduling(logger as Test.Logger) as Boolean {
    resetFixture();
    var at=utc(2026,9,30,6,0);
    AlarmClock.setTestTime(at,0);
    for (var i=0;i<MAX_ALARMS;i++) { repeatAlarm(6,i,DAYS_ALL); }
    Test.assert(AlarmStore.isFull());
    Test.assert(AlarmEngine.secsUntilNextTarget(at) == 0);
    Test.assert(AlarmEngine.evaluate(at) == AlarmStore.id(AlarmStore.getAlarms()[0]));
    return true;
}
