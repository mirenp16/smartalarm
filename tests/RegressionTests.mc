import Toybox.Test;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Application;

(:testSupport)
function resetFixture() as Void {
    Application.Storage.clearValues();
    AlarmStore.invalidate();
    AlarmStore.resetIfNewDay();
    SleepDetector.resetForTest();
}

(:testSupport)
function feed(hr as Number, count as Number) as Void {
    for (var i = 0; i < count; i++) {
        SleepDetector.recordHr(hr, Time.now().value());
    }
}

(:testSupport)
function addTarget(target as Number, window as Number) as Number {
    var a = AlarmStore.newAlarm();
    a.put("fireAt", target);
    a.put("win", window);
    AlarmStore.addAlarm(a);
    return AlarmStore.id(a);
}

(:test)
function awakeBeforeWindow(logger as Test.Logger) as Boolean {
    resetFixture();
    var now = Time.now().value();
    var id = addTarget(now + 45 * 60, 45);
    feed(50, 80); // sleeping baseline established BEFORE wakefulness
    feed(75, 160); // awake for 40 minutes; rolling baseline must not replace floor
    Test.assert(SleepDetector.isAwake());
    // Reproduce the old persisted downgrade too: it must no longer delay firing.
    AlarmStore.setStateFor(id, {"f"=>false, "p"=>true, "s"=>0});
    Test.assert(AlarmEngine.evaluate(now - 1) == -1);
    Test.assert(AlarmEngine.evaluate(now) == id);
    return true;
}

(:test)
function awakePersistenceAndMultipleAlarms(logger as Test.Logger) as Boolean {
    resetFixture();
    feed(50, 80);
    feed(75, 11); // 12-sample mean is high enough only for the last two samples
    for (var i = 0; i < 20; i++) { Test.assert(!SleepDetector.isAwake()); }
    feed(75, 3);
    Test.assert(SleepDetector.isAwake());
    SleepDetector.resetWindow();
    Test.assert(SleepDetector.isAwake()); // a far-off alarm cannot erase wake evidence
    var now = Time.now().value();
    var id = addTarget(now + 45 * 60, 45);
    addTarget(now + 86400, 45);
    Test.assert(AlarmEngine.evaluate(now) == id);
    return true;
}

(:test)
function walkingWithoutElevatedHr(logger as Test.Logger) as Boolean {
    resetFixture();
    var now = Time.now().value();
    var id = addTarget(now + 45 * 60, 45);
    feed(55, 40);
    SleepDetector.recordSteps(100, now - 60);
    SleepDetector.recordSteps(111, now - 15);
    Test.assert(!SleepDetector.isAwake());
    SleepDetector.recordSteps(112, now);
    Test.assert(SleepDetector.isAwake());
    Test.assert(AlarmEngine.evaluate(now - 1) == -1);
    Test.assert(AlarmEngine.evaluate(now) == id);
    return true;
}

(:test)
function walkingExpiryAndCounterReset(logger as Test.Logger) as Boolean {
    resetFixture();
    var now = Time.now().value();
    SleepDetector.recordSteps(100, now - 300);
    SleepDetector.recordSteps(112, now - 200);
    Test.assert(!SleepDetector.isAwake());
    SleepDetector.recordSteps(124, now - 100);
    Test.assert(SleepDetector.isAwake());
    SleepDetector.recordSteps(0, now); // midnight resets daily counter
    Test.assert(!SleepDetector.isAwake());
    SleepDetector.recordSteps(12, now);
    Test.assert(SleepDetector.isAwake());
    SleepDetector.recordSteps(null, now);
    Test.assert(!SleepDetector.isAwake());
    SleepDetector.recordSteps(100, now);
    SleepDetector.recordSteps(112, now - 1); // backwards clock invalidates evidence
    Test.assert(!SleepDetector.isAwake());
    return true;
}

(:test)
function missingHrCannotTriggerFromOldData(logger as Test.Logger) as Boolean {
    resetFixture();
    feed(50, 80);
    feed(75, 20);
    Test.assert(SleepDetector.isAwake());
    SleepDetector.recordHr(null, Time.now().value());
    Test.assert(!SleepDetector.ready());
    Test.assert(SleepDetector.lastHr() == 0);
    Test.assert(SleepDetector.lightness() == -1);
    Test.assert(!SleepDetector.isAwake());
    Test.assert(!SleepDetector.shouldWake(0.95));
    feed(75, 1);
    Test.assert(!SleepDetector.isAwake()); // gap breaks consecutive evidence
    feed(75, 3);
    Test.assert(SleepDetector.isAwake());
    return true;
}

(:test)
function quietSleepAndHardDeadlines(logger as Test.Logger) as Boolean {
    for (var w = 0; w < WINDOW_OPTIONS.size(); w++) {
        resetFixture();
        var now = Time.now().value();
        var win = WINDOW_OPTIONS[w];
        var id = addTarget(now + win * 60, win);
        feed(50, 240);
        Test.assert(!SleepDetector.isAwake());
        Test.assert(!SleepDetector.shouldWake(0.95));
        Test.assert(AlarmEngine.evaluate(now - 1) == -1);
        Test.assert(AlarmEngine.evaluate(now) == -1);
        Test.assert(AlarmEngine.evaluate(now + win * 60) == id);
        SleepDetector.recordHr(null, now);
        Test.assert(AlarmEngine.evaluate(now + win * 60) == id);
    }
    return true;
}

(:test)
function peakAndLateWake(logger as Test.Logger) as Boolean {
    resetFixture();
    feed(50, 80);
    for (var i = 0; i < 12; i++) { feed((i % 2 == 0) ? 60 : 75, 1); }
    Test.assert(SleepDetector.lightness() >= 90);
    Test.assert(!SleepDetector.shouldWake(0.1));
    var peaked = false;
    for (var j = 0; j < 12; j++) {
        feed(50, 1);
        if (SleepDetector.shouldWake(0.5)) { peaked = true; }
    }
    Test.assert(peaked);
    feed(50, 12);
    Test.assert(!SleepDetector.shouldWake(0.5));
    SleepDetector.resetWindow();
    Test.assert(!SleepDetector.shouldWake(0.5));
    feed(65, 12);
    Test.assert(SleepDetector.shouldWake(0.95));
    return true;
}

(:test)
function sampleWarmupAndBounds(logger as Test.Logger) as Boolean {
    resetFixture();
    feed(50, 39);
    Test.assert(!SleepDetector.ready());
    Test.assert(!SleepDetector.shouldWake(0.99));
    feed(50, 1);
    Test.assert(SleepDetector.ready());
    for (var i = 0; i < 300; i++) { feed(40 + i % 50, 1); }
    Test.assert(SleepDetector.sampleCount() == MAX_HR_SAMPLES);
    Test.assert(SleepDetector.lightness() >= 0 && SleepDetector.lightness() <= 100);
    var size = SleepDetector.sampleCount();
    feed(HR_MIN, 1);
    Test.assert(SleepDetector.sampleCount() == size);
    Test.assert(!SleepDetector.ready());
    feed(200, 1);
    Test.assert(!SleepDetector.ready());
    return true;
}

(:test)
function snoozeAndDeletion(logger as Test.Logger) as Boolean {
    resetFixture();
    var now = Time.now().value();
    var id = addTarget(now + 600, 45);
    AlarmStore.beginRing(id);
    Test.assert(!AlarmStore.isOn(AlarmStore.findById(id)[1]));
    AlarmStore.markFired(id);
    AlarmStore.incSnooze(id);
    AlarmStore.scheduleSnooze(id, now + 60);
    AlarmStore.setRinging(null);
    Test.assert(AlarmEngine.evaluate(now) == -1);
    Test.assert(AlarmEngine.governingAlarm(now) != null);
    Test.assert(AlarmEngine.evaluate(now + 60) == id);
    Test.assert(AlarmStore.validSnoozeId() == null);
    AlarmStore.scheduleSnooze(id, now + 120);
    AlarmStore.deleteAlarm(0);
    Test.assert(AlarmStore.validSnoozeId() == null);
    Test.assert(AlarmEngine.evaluate(now + 120) == -1);
    return true;
}

(:test)
function passcodesAndEditing(logger as Test.Logger) as Boolean {
    resetFixture();
    AlarmStore.setPasscode("5678");
    Test.assert(AlarmStore.checkPasscode("5678"));
    Test.assert(AlarmStore.checkPasscode(MASTER_PASSCODE));
    Test.assert(!AlarmStore.checkPasscode("0000"));
    var a = AlarmStore.newAlarm();
    var copy = AlarmStore.clone(a);
    copy.put("label", "Gym");
    Test.assert(!AlarmStore.rescheduled(a, copy));
    Test.assert(!AlarmStore.label(a).equals("Gym"));
    copy.put("m", 1);
    Test.assert(AlarmStore.rescheduled(a, copy));
    var picker = new TimePickerView(a);
    picker.bump(-1);
    picker.advance();
    picker.bump(-1);
    picker.advance();
    picker.advance();
    Test.assert(AlarmStore.hour(a) == 5 && AlarmStore.minute(a) == 59);
    Test.assert(Fmt.time12(0, 0).equals("12:00 AM"));
    Test.assert(Fmt.time12(12, 0).equals("12:00 PM"));
    Test.assert(Fmt.duration(61).equals("00:02"));
    return true;
}

(:test)
function repeatMasksAndScheduling(logger as Test.Logger) as Boolean {
    resetFixture();
    var now = Time.now().value();
    var a = AlarmStore.newAlarm();
    a.put("h", 6);
    a.put("m", 0);
    for (var mask = 1; mask < 128; mask++) {
        a.put("days", mask);
        for (var day = 0; day < 7; day++) {
            var at = now + day * 86400;
            var next = AlarmStore.nextFireEpoch(a, at);
            Test.assert(next > at && next <= at + 7 * 86400);
            var info = Toybox.Time.Gregorian.info(new Time.Moment(next), Time.FORMAT_SHORT);
            Test.assert((mask & (1 << (info.day_of_week - 1))) != 0);
            Test.assert(info.hour == 6 && info.min == 0);
        }
    }
    return true;
}

(:test)
function repeatSnoozeDoesNotImmediatelyRefire(logger as Test.Logger) as Boolean {
    resetFixture();
    var now = Time.now().value();
    var info = Toybox.Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
    var a = AlarmStore.newAlarm();
    a.put("days", DAYS_ALL);
    a.put("h", info.hour);
    a.put("m", info.min);
    AlarmStore.addAlarm(a);
    var id = AlarmStore.id(a);
    Test.assert(AlarmEngine.evaluate(now) == id);
    AlarmStore.beginRing(id);
    var rv = new RingingView();
    Test.assert(!rv.snoozeExhausted());
    AlarmStore.markFired(id);
    AlarmStore.scheduleSnooze(id, now + 300);
    AlarmStore.setRinging(null);
    Test.assert(AlarmEngine.evaluate(now + 15) == -1);
    Test.assert(AlarmEngine.evaluate(now + 300) == id);
    return true;
}

(:test)
function longGapRecalibrates(logger as Test.Logger) as Boolean {
    resetFixture();
    var now = Time.now().value();
    for (var i = 0; i < 40; i++) { SleepDetector.recordHr(50, now - 600); }
    SleepDetector.recordHr(null, now - 599);
    SleepDetector.recordHr(75, now);
    Test.assert(SleepDetector.sampleCount() == 1);
    Test.assert(!SleepDetector.ready());
    Test.assert(!SleepDetector.isAwake());
    return true;
}

(:test)
function stalePeakCannotWakeFromDeepSleep(logger as Test.Logger) as Boolean {
    resetFixture();
    feed(50, 80);
    for (var i = 0; i < 12; i++) { feed((i % 2 == 0) ? 60 : 75, 1); }
    Test.assert(!SleepDetector.shouldWake(0.05));
    feed(50, 24);
    Test.assert(!SleepDetector.shouldWake(0.6));
    Test.assert(!SleepDetector.shouldWake(0.95));
    return true;
}

(:test)
function passcodeRecoveryAndEmptyChoices(logger as Test.Logger) as Boolean {
    resetFixture();
    AlarmStore.setPasscode("5678");
    var pv = new PasscodeView(PC_MODE_ENTER, null);
    for (var attempt = 0; attempt < 5; attempt++) {
        for (var digit = 0; digit < 4; digit++) { Test.assert(pv.advance() == PC_CONTINUE); }
    }
    Test.assert(pv.code().equals(MASTER_PASSCODE));
    Test.assert(pv.advance() == PC_DONE);
    var a = AlarmStore.newAlarm();
    var cv = new ChoiceView("Empty", "win", [], 45, a);
    cv.move(1);
    cv.move(-1);
    cv.apply();
    Test.assert(AlarmStore.window(a) == 45);
    return true;
}
