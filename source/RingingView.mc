// RingingView.mc
// Shown when an alarm fires (foreground only — the foreground can vibrate/beep,
// the background cannot). Alerts on a repeating timer.
//
// Controls (deliberately limited so it can't be dismissed by accident):
//   START            -> Snooze   (green)
//   LIGHT or BACK    -> Dismiss / "I'm awake"  (red)
//   UP / DOWN / tap  -> ignored
//
// Snooze is capped by Max Snoozes (Settings). At the cap only Dismiss works.

import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

class RingingView extends WatchUi.View {

    private var _timer as Timer.Timer?;
    private var _alarm as Dictionary?;
    private var _w as Number = 260;
    private var _h as Number = 260;
    private var _cx as Number = 130;
    private var _cy as Number = 130;

    function initialize() {
        View.initialize();
        var id = AlarmStore.ringingId();
        if (id != null) {
            var found = AlarmStore.findById(id);
            _alarm = found[1];
        }
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    function onShow() as Void {
        alert();
        if (_timer == null) {
            _timer = new Timer.Timer();
            _timer.start(method(:onTick), 3000, true);
        }
    }

    function onHide() as Void { stopTimer(); }

    function onTick() as Void {
        alert();
        WatchUi.requestUpdate();
    }

    function alert() as Void {
        var mode = (_alarm != null) ? AlarmStore.mode(_alarm) : MODE_BOTH;
        try {
            if (mode == MODE_BOTH || mode == MODE_SOUND) {
                Attention.playTone(Attention.TONE_ALARM);
            }
            if (mode == MODE_BOTH || mode == MODE_VIBE) {
                Attention.vibrate([new Attention.VibeProfile(100, 1500)]);
            }
        } catch (e) {
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var label = (_alarm != null) ? AlarmStore.label(_alarm) : "Alarm";
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var atMax = snoozeExhausted();

        // Label
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 56, Graphics.FONT_MEDIUM, label, Graphics.TEXT_JUSTIFY_CENTER);

        // Current time (large)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 20, Graphics.FONT_LARGE, Fmt.time12(now.hour, now.min),
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Snoozes remaining
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var info = atMax
            ? "No snoozes left"
            : ((AlarmStore.maxSnooze() - snoozeCount()).format("%d") + " snoozes left");
        dc.drawText(_cx, _cy + 30, Graphics.FONT_XTINY, info, Graphics.TEXT_JUSTIFY_CENTER);

        // Button hints
        var green = atMax ? null : ("Snooze " + AlarmStore.snoozeMinutes().format("%d") + "m");
        Ui.hints(dc, _w, _h, green, "I'm awake");
    }

    function snoozeCount() as Number {
        var id = AlarmStore.ringingId();
        return (id != null) ? AlarmStore.snoozeCount(id) : 0;
    }
    function snoozeExhausted() as Boolean { return snoozeCount() >= AlarmStore.maxSnooze(); }

    function stopTimer() as Void {
        if (_timer != null) { _timer.stop(); _timer = null; }
    }

    function doSnooze() as Void {
        var id = AlarmStore.ringingId();
        if (id == null) { close(); return; }
        if (snoozeExhausted()) { return; }   // must dismiss instead
        AlarmStore.incSnooze(id);
        var until = Time.now().value() + AlarmStore.snoozeMinutes() * 60;
        AlarmStore.scheduleSnooze(id, until);
        AlarmStore.setRinging(null);
        close();
    }

    function doDismiss() as Void {
        var id = AlarmStore.ringingId();
        if (id != null) { AlarmStore.markFired(id); }
        AlarmStore.setRinging(null);
        AlarmStore.setSnoozeUntil(null);
        close();
    }

    private function close() as Void {
        stopTimer();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class RingingDelegate extends WatchUi.BehaviorDelegate {

    private var _view as RingingView;

    function initialize(view as RingingView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // START = snooze
    function onSelect() as Boolean { _view.doSnooze(); return true; }

    // LIGHT or BACK = dismiss
    function onBack() as Boolean { _view.doDismiss(); return true; }
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_LIGHT) {
            _view.doDismiss();
            return true;
        }
        return false;
    }

    // Swallow everything else so the alarm can't be dismissed by accident.
    function onNextPage() as Boolean { return true; }
    function onPreviousPage() as Boolean { return true; }
    function onTap(evt as WatchUi.ClickEvent) as Boolean { return true; }
}
