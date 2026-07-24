// BedsideView.mc  ("Active Alarm" mode)
// The reliable, on-time, prompt-free path. Runs in the foreground so it can
// vibrate/beep and open the ringing screen directly. Shows the next alarm and the
// current time on a near-black screen (AMOLED-friendly).
//
// Battery-minimal: wakes every 15 s just to compare the clock; it only touches the
// heart-rate/motion sensors while inside a Sleep Cycle Window (AlarmEngine does the
// sensor work only then).
//
// Hard to leave on purpose: exit requires BACK, then UP within 5 seconds — so you
// can't drop out of it in your sleep. Single button presses do nothing.

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
        // Silence the background service while we own the foreground.
        SmartAlarmApp.unregisterBackground();
        if (AlarmStore.ringingId() == null) { _ringingShown = false; }
        if (_timer == null) {
            _timer = new Timer.Timer();
            _timer.start(method(:onTick), 15000, true);   // every 15 s
        }
    }

    function onHide() as Void { stopTimer(); }

    function onTick() as Void {
        // Cancel a stale exit-arm.
        if (_exitArmed && (Time.now().value() - _armSecs) > 5) {
            _exitArmed = false;
        }

        if (AlarmStore.ringingId() != null) { showRinging(); return; }

        var id = AlarmEngine.evaluate(Time.now().value());
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

        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var next = AlarmEngine.nextAlarm(Time.now().value());
        var vc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Title (small, grey, one line)
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 80, Graphics.FONT_XTINY, "Active Alarm Mode", vc);

        // Current time (grey, smaller)
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 52, Graphics.FONT_XTINY, "Current Time", vc);
        dc.setColor(0x999999, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 26, Graphics.FONT_SMALL, Fmt.time12(now.hour, now.min), vc);

        // Next alarm (white, bigger)
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + 4, Graphics.FONT_XTINY, "Next Alarm", vc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var nextStr = (next != null)
            ? Fmt.time12(AlarmStore.hour(next), AlarmStore.minute(next))
            : "None";
        dc.drawText(_cx, _cy + 38, Graphics.FONT_MEDIUM, nextStr, vc);

        // Exit hint + button arrows (BACK then UP)
        if (_exitArmed) {
            dc.setColor(0x33AAFF, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _h * 82 / 100, Graphics.FONT_XTINY, "Press UP now to exit", vc);
        } else {
            dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _h * 82 / 100, Graphics.FONT_XTINY, "BACK and then UP to Exit", vc);
        }
        Ui.back(dc, _w, _h, "BACK");
        Ui.up(dc, _w, _h, "UP");
    }

    // Called by the delegate.
    function armExit() as Void {
        _exitArmed = true;
        _armSecs = Time.now().value();
        WatchUi.requestUpdate();
    }

    function tryExit() as Boolean {
        if (_exitArmed && (Time.now().value() - _armSecs) <= 5) {
            return true;
        }
        return false;
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

    // Handle raw keys so single presses can't leave the screen.
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var k = evt.getKey();
        if (k == WatchUi.KEY_ESC) {          // BACK arms the exit
            _view.armExit();
        } else if (k == WatchUi.KEY_UP) {    // UP completes it (if armed)
            tryLeave();
        }
        return true;                          // swallow everything else
    }

    // Also swallow the mapped behaviours so nothing exits by accident.
    function onBack() as Boolean { _view.armExit(); return true; }
    function onPreviousPage() as Boolean { tryLeave(); return true; }
    function onNextPage() as Boolean { return true; }
    function onSelect() as Boolean { return true; }
    function onTap(evt as WatchUi.ClickEvent) as Boolean { return true; }

    private function tryLeave() as Void {
        if (_view.tryExit()) {
            _view.stopTimer();
            SmartAlarmApp.syncBackground();
            var lv = new AlarmListView();
            WatchUi.switchToView(lv, new AlarmListDelegate(lv), WatchUi.SLIDE_DOWN);
        }
    }
}
