// RingingView.mc
// The screen shown when an alarm fires. The foreground CAN play tones/vibrate
// (the background cannot), so all real alerting happens here on a repeating timer.
//
// Controls (buttons + touch, per your choice):
//   • START / UP / DOWN, or tap the big Snooze button  -> snooze
//   • BACK, or tap the small Dismiss bar               -> dismiss
//
// Snooze is capped by maxSnooze (default 5). When the cap is hit, only Dismiss
// works (Phase 2 will escalate this into the SOS alarm instead).

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

    // Start alerting as soon as the screen appears.
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

    // Plays tone and/or vibration according to the alarm's alert mode.
    // Wrapped in try/catch so a device without a tone generator can't crash.
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

        // Integer layout positions (avoid Float args to Dc methods).
        var labelY = _h * 14 / 100;
        var timeY  = _h * 26 / 100;
        var snLeft = _w * 15 / 100;
        var snTop  = _h * 52 / 100;
        var snW    = _w * 70 / 100;
        var snH    = _h * 22 / 100;
        var remY   = _h * 80 / 100;
        var disLeft = _w * 30 / 100;
        var disTop  = _h * 87 / 100;
        var disW    = _w * 40 / 100;
        var disH    = _h * 11 / 100;

        // Label
        dc.setColor(0x00CC66, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, labelY, Graphics.FONT_SMALL, label, Graphics.TEXT_JUSTIFY_CENTER);

        // Current time (large). Regular font because the string includes AM/PM.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, timeY, Graphics.FONT_MEDIUM,
                    Fmt.time12(now.hour, now.min), Graphics.TEXT_JUSTIFY_CENTER);

        // Snooze button (big, lower-middle)
        var atMax = snoozeExhausted();
        dc.setColor(atMax ? 0x333333 : 0x004422, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(snLeft, snTop, snW, snH, 12);
        dc.setColor(atMax ? 0x777777 : 0x00CC66, Graphics.COLOR_TRANSPARENT);
        var mins = AlarmStore.snoozeMinutes();
        var snText = atMax ? "No snoozes left" : ("Snooze " + mins.format("%d") + " min");
        dc.drawText(_cx, snTop + snH / 2 - 12, Graphics.FONT_TINY, snText,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Snoozes remaining
        if (!atMax) {
            var left = AlarmStore.maxSnooze() - snoozeCount();
            dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, remY, Graphics.FONT_XTINY,
                        left.format("%d") + " snoozes left", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Dismiss bar (small, bottom)
        dc.setColor(0x662222, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(disLeft, disTop, disW, disH, 10);
        dc.setColor(0xFF6666, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, disTop + disH / 2 - 12, Graphics.FONT_XTINY, "Dismiss",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ── State helpers ────────────────────────────────────────────────────────

    function snoozeCount() as Number {
        var id = AlarmStore.ringingId();
        return (id != null) ? AlarmStore.snoozeCount(id) : 0;
    }

    function snoozeExhausted() as Boolean {
        return snoozeCount() >= AlarmStore.maxSnooze();
    }

    function stopTimer() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    function doSnooze() as Void {
        var id = AlarmStore.ringingId();
        if (id == null) { close(); return; }
        if (snoozeExhausted()) { doDismiss(); return; }

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

    // Which vertical zone a tap fell in.
    function tapIsDismiss(y as Number) as Boolean { return y >= _h * 87 / 100; }
    function tapIsSnooze(y as Number) as Boolean {
        return y >= _h * 52 / 100 && y < _h * 87 / 100;
    }
}

class RingingDelegate extends WatchUi.BehaviorDelegate {

    private var _view as RingingView;

    function initialize(view as RingingView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // Physical buttons: START/UP/DOWN snooze, BACK dismisses.
    function onSelect() as Boolean { _view.doSnooze(); return true; }
    function onNextPage() as Boolean { _view.doSnooze(); return true; }
    function onPreviousPage() as Boolean { _view.doSnooze(); return true; }

    function onBack() as Boolean { _view.doDismiss(); return true; }

    // Touch: bottom bar dismisses, middle area snoozes.
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var xy = evt.getCoordinates();
        var y = xy[1];
        if (_view.tapIsDismiss(y)) {
            _view.doDismiss();
        } else if (_view.tapIsSnooze(y)) {
            _view.doSnooze();
        }
        return true;
    }
}
