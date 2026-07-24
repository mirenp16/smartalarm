// BedsideView.mc
// The reliable, on-time, prompt-free path. You launch this at bedtime (ideally on
// the charger) and it stays in the foreground all night. Because it's foreground,
// it can vibrate/beep and open the ringing screen directly — no system prompt.
//
// Battery-minimal by design:
//   * Screen is drawn almost entirely BLACK (on AMOLED, black pixels are ~off).
//   * It wakes only once a minute to check the clock.
//   * It samples heart rate / motion ONLY while inside a Sleep Cycle Window
//     (AlarmEngine does the sensor work only then); the rest of the night it just
//     compares the time, which is nearly free.
//
// BACK exits Bedside Mode. Other buttons are ignored so you can't leave by accident.

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
    private var _w as Number = 260;
    private var _h as Number = 260;
    private var _cx as Number = 130;
    private var _cy as Number = 130;

    function initialize() { View.initialize(); }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    // Start ticking when shown (also when returning from the ringing screen).
    function onShow() as Void {
        // While Bedside Mode owns the foreground, silence the background service
        // so its "open the app?" prompt can't pop over us. Restored on exit.
        SmartAlarmApp.unregisterBackground();
        if (AlarmStore.ringingId() == null) { _ringingShown = false; }
        if (_timer == null) {
            _timer = new Timer.Timer();
            _timer.start(method(:onTick), 60000, true);   // once a minute
        }
    }

    // Stop ticking while the ringing screen is on top (it has its own timer).
    function onHide() as Void { stopTimer(); }

    function onTick() as Void {
        var now = Time.now().value();

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
        // Mostly black to keep AMOLED draw near zero.
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);

        // Dim clock (low luminance = low battery).
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 24, Graphics.FONT_MEDIUM, Fmt.time12(now.hour, now.min),
                    Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + 14, Graphics.FONT_XTINY, "Bedside Mode active",
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(_cx, _h * 82 / 100, Graphics.FONT_XTINY, "BACK: Exit",
                    Graphics.TEXT_JUSTIFY_CENTER);
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

    // BACK exits Bedside Mode and restores the background service.
    function onBack() as Boolean {
        _view.stopTimer();
        SmartAlarmApp.syncBackground();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        return true;
    }

    // Ignore everything else so we can't leave by accident.
    function onSelect() as Boolean { return true; }
    function onNextPage() as Boolean { return true; }
    function onPreviousPage() as Boolean { return true; }
    function onTap(evt as WatchUi.ClickEvent) as Boolean { return true; }
}
