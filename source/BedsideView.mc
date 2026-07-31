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
    private var _w as Number = 260;
    private var _h as Number = 260;
    private var _cx as Number = 130;
    private var _cy as Number = 130;

    function initialize() { View.initialize(); }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    function onShow() as Void {
        if (AlarmStore.ringingId() == null) { _ringingShown = false; }
        if (_timer == null) {
            _timer = new Timer.Timer();
            _timer.start(method(:onTick), 15000, true);
        }
    }

    function onHide() as Void { stopTimer(); }

    function onTick() as Void {
        var now = Time.now().value();
        if (_exitArmed && (now - _armSecs) > 5) { _exitArmed = false; }

        if (AlarmStore.ringingId() != null) { showRinging(); return; }

        var id = AlarmEngine.evaluate(now);
        if (id >= 0) {
            AlarmStore.beginRing(id);
            showRinging();
            return;
        }
        WatchUi.requestUpdate();
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

        // Title
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 78, Graphics.FONT_XTINY, "Active Alarm Mode", vc);

        // Current time
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 46, Graphics.FONT_XTINY, "Current Time", vc);
        dc.setColor(0x999999, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 22, Graphics.FONT_SMALL, Fmt.time12(now.hour, now.min), vc);

        // Next alarm (shows the snooze time if an alarm is snoozed)
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + 14, Graphics.FONT_XTINY, "Next Alarm", vc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + 44, Graphics.FONT_MEDIUM, nextAlarmStr(), vc);

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
        var snU = AlarmStore.snoozeUntil();
        if (snU != null && snU > nowSecs) {
            var si = Gregorian.info(new Time.Moment(snU), Time.FORMAT_SHORT);
            return Fmt.time12(si.hour, si.min);
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

    function armExit() as Void {
        _exitArmed = true;
        _armSecs = Time.now().value();
        revealControls();
    }
    function exitReady() as Boolean {
        return _exitArmed && (Time.now().value() - _armSecs) <= 5;
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

    // UP completes the exit if armed; otherwise just reveals the controls.
    function onPreviousPage() as Boolean {
        if (_view.exitReady()) {
            _leave();
        } else {
            _view.revealControls();
        }
        return true;
    }

    // Other buttons only reveal the controls.
    function onSelect() as Boolean { _view.revealControls(); return true; }
    function onNextPage() as Boolean { _view.revealControls(); return true; }
    function onTap(evt as WatchUi.ClickEvent) as Boolean { _view.revealControls(); return true; }

    private function _leave() as Void {
        _view.stopTimer();
        MainListMenu.show(WatchUi.SLIDE_DOWN);
    }
}
