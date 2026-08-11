// BedsideView.mc  ("Active Alarm Mode")
// The only place alarms ring. Runs in the foreground so it can vibrate/beep and
// open the ringing screen directly. You enter it at bedtime; ON alarms fire while
// it's up. Battery-minimal: near-black screen, checks the clock every 15 s, and
// only samples sensors while inside a Sleep Cycle Window.
//
// When idle the screen shows ONLY the title, current time and next alarm (dim, so
// it barely lights the AMOLED). Pressing any button reveals the exit controls for
// a few seconds. Exit is deliberately a two-step combo: BACK, then UP.

import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

class BedsideView extends WatchUi.View {

    private var _timer as Timer.Timer?;
    private var _ringingShown as Boolean = false;
    private var _exitArmed as Boolean = false;
    private var _armSecs as Number = 0;
    private var _controlsSecs as Number = -100;    // when controls were last revealed
    private var _lastDrawMin as Number = -1;       // throttles redraws to once a minute
    private var _tickMs as Number = 0;             // current timer cadence
    private var _w as Number = 360;
    private var _h as Number = 360;
    private var _cx as Number = 180;
    private var _cy as Number = 180;

    function initialize() { View.initialize(); }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    // Set by the ringing screen once an alarm has been dismissed and there is
    // nothing left to wait for - we then close Active Alarm Mode automatically
    // instead of making the user enter the passcode a second time.
    public static var exitRequested as Boolean = false;

    function onShow() as Void {
        if (exitRequested) {
            exitRequested = false;
            stopTimer();
            SessionKeeper.stop();
            MainListMenu.show(WatchUi.SLIDE_DOWN);
            return;
        }

        // Anchor the app in the foreground so a palm touch can't drop out of it.
        SessionKeeper.start();

        if (AlarmStore.ringingId() == null) { _ringingShown = false; }
        startTimer(pickInterval());
    }

    // 15 s near an alarm, 60 s the rest of the night (4x fewer CPU wakeups).
    private function pickInterval() as Number {
        var d = AlarmEngine.secsUntilNextTarget(Time.now().value());
        if (d >= 0 && d <= FAST_TICK_WITHIN_SECS) { return TICK_FAST_MS; }
        return TICK_SLOW_MS;
    }

    private function startTimer(ms as Number) as Void {
        if (_timer != null && _tickMs == ms) { return; }   // already correct
        stopTimer();
        _tickMs = ms;
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), ms, true);
    }

    function onHide() as Void { stopTimer(); }

    // The whole body is guarded. This runs unattended for hours, and a single
    // uncaught exception used to kill the app (the "IQ!" screen) and take the
    // alarm with it. Sleep sampling is best-effort; the alarm itself must survive.
    function onTick() as Void {
        var now = Time.now().value();
        if (_exitArmed && (now - _armSecs) > EXIT_ARM_SECS) { _exitArmed = false; }

        try {
            // Only read the heart-rate sensor when a wake window is approaching.
            // For most of the night there is nothing to detect, so staying idle
            // here saves a large amount of battery.
            if (AlarmEngine.shouldSample(now)) {
                SleepDetector.sample();
            }
        } catch (e) {
            // Sensor hiccup - keep going, the deadline will still fire.
        }

        try {
            if (AlarmStore.ringingId() != null) { showRinging(); return; }

            var id = AlarmEngine.evaluate(now);
            if (id >= 0) {
                AlarmStore.beginRing(id);
                showRinging();
                return;
            }
        } catch (e2) {
            // Never let a scheduling error stop the clock.
        }

        // Speed up as the alarm approaches, slow down again afterwards.
        startTimer(pickInterval());

        // Only redraw when the displayed minute actually changes - redrawing
        // every 15 s all night was wasted work and extra allocation.
        var mins = now / 60;
        if (mins != _lastDrawMin) {
            _lastDrawMin = mins;
            WatchUi.requestUpdate();
        }
    }

    private function showRinging() as Void {
        if (!_ringingShown) {
            _ringingShown = true;
            var rv = new RingingView();
            WatchUi.pushView(rv, new RingingDelegate(rv), WatchUi.SLIDE_UP);
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var vc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);

        // Title, curved along the top of the bezel (falls back to straight text).
        Ui.labelSized(dc, _w, _h, 90, 0xAAAAAA, "Active Alarm Mode", 28);

        // Current time
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 62, Graphics.FONT_XTINY, "Current Time", vc);
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 32, Graphics.FONT_MEDIUM, Fmt.time12(now.hour, now.min), vc);

        // Next alarm (shows the snooze time if an alarm is snoozed)
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + 14, Graphics.FONT_XTINY, "Next Alarm", vc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + 48, Graphics.FONT_LARGE, nextAlarmStr(), vc);

        // Exit controls only appear briefly after a button press.
        if (controlsVisible()) {
            dc.setColor(_exitArmed ? 0x33AAFF : 0x777777, Graphics.COLOR_TRANSPARENT);
            var hint = _exitArmed ? "Press UP now to exit" : "BACK then UP to exit";
            dc.drawText(_cx, _h * 84 / 100, Graphics.FONT_XTINY, hint, vc);
            Ui.back(dc, _w, _h, "BACK");
            Ui.up(dc, _w, _h, "UP");
        }
    }

    function nextAlarmStr() as String {
        var nowSecs = Time.now().value();
        // Only show a snooze time if that alarm still exists (validSnoozeId
        // clears the snooze when its alarm has been deleted).
        if (AlarmStore.validSnoozeId() != null) {
            var snU = AlarmStore.snoozeUntil();
            if (snU != null && snU > nowSecs) {
                var si = Gregorian.info(new Time.Moment(snU), Time.FORMAT_SHORT);
                return Fmt.time12(si.hour, si.min);
            }
        }
        var next = AlarmEngine.nextAlarm(nowSecs);
        return (next != null) ? Fmt.time12(AlarmStore.hour(next), AlarmStore.minute(next)) : "None";
    }

    // ── Controls / exit ──────────────────────────────────────────────────────

    function revealControls() as Void {
        _controlsSecs = Time.now().value();
        WatchUi.requestUpdate();
    }
    function controlsVisible() as Boolean {
        return (Time.now().value() - _controlsSecs) <= 6;
    }

    // BACK arms the exit. It must be followed IMMEDIATELY by UP - any other
    // button in between calls disarm() and the sequence starts over.
    function armExit() as Void {
        _exitArmed = true;
        _armSecs = Time.now().value();
        revealControls();
    }
    function disarmExit() as Void {
        _exitArmed = false;
        revealControls();
    }
    function exitReady() as Boolean {
        return _exitArmed && (Time.now().value() - _armSecs) <= EXIT_ARM_SECS;
    }

    function stopTimer() as Void {
        if (_timer != null) { _timer.stop(); _timer = null; }
    }
}

class BedsideDelegate extends WatchUi.BehaviorDelegate {

    private var _view as BedsideView;

    function initialize(view as BedsideView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // BACK reveals controls and arms the exit.
    function onBack() as Boolean { _view.armExit(); return true; }

    // UP completes the exit ONLY if BACK was the button pressed immediately
    // before it. Otherwise it just reveals the controls (and stays disarmed).
    function onPreviousPage() as Boolean {
        if (_view.exitReady()) {
            _leave();
        } else {
            _view.disarmExit();
        }
        return true;
    }

    // Any other button breaks the BACK->UP sequence.
    function onSelect() as Boolean { _view.disarmExit(); return true; }
    function onNextPage() as Boolean { _view.disarmExit(); return true; }

    // ── Touchscreen fully disabled ───────────────────────────────────────────
    // Every touch gesture is swallowed (returning true stops it being handled),
    // so a stray touch or swipe in your sleep can't disturb Active Alarm Mode.
    function onTap(evt as WatchUi.ClickEvent) as Boolean { return true; }
    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean { return true; }
    function onHold(evt as WatchUi.ClickEvent) as Boolean { return true; }
    function onDrag(evt) as Boolean { return true; }
    function onRelease(evt as WatchUi.ClickEvent) as Boolean { return true; }
    function onFlick(evt) as Boolean { return true; }

    // Leaving Active Alarm Mode. Whether a passcode is needed is decided by the
    // NEXT upcoming alarm - if its Passcode toggle is off, BACK->UP just exits.
    // With no upcoming alarm at all, no code is needed either.
    private function _leave() as Void {
        // governingAlarm counts a snoozed/ringing alarm too, so hitting snooze
        // can't be used to slip out without the passcode.
        var next = AlarmEngine.governingAlarm(Time.now().value());
        if (next != null && AlarmStore.passcodeOn(next)) {
            var pv = new PasscodeView(PC_MODE_ENTER, method(:finishLeave));
            WatchUi.pushView(pv, new PasscodeDelegate(pv), WatchUi.SLIDE_UP);
            return;
        }
        finishLeave();
    }

    // Runs AFTER the passcode screen has closed, so switchToView replaces the
    // Active Alarm view (not the passcode view) and the exit actually sticks.
    function finishLeave() as Void {
        _view.stopTimer();
        SessionKeeper.stop();     // release the foreground anchor
        MainListMenu.show(WatchUi.SLIDE_DOWN);
    }
}
