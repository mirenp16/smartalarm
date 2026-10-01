import Toybox.Test;
import Toybox.Lang;

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
