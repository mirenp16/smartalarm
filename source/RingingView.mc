// RingingView.mc
// Shown when an alarm fires (foreground only can vibrate/beep). Alerts on a timer.
//
// Controls (nothing dismisses by accident):
//   START            -> Snooze              (red)
//   BACK, then UP    -> "I'm Awake!"         (green)  -- same deliberate combo as
//                                                        exiting Active Alarm mode
//   anything else    -> ignored (keeps vibrating)
//
// When snoozes run out, only BACK-then-UP ("I'm Awake!") stops it.

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
    private var _awakeArmed as Boolean = false;
    private var _armSecs as Number = 0;
    private var _controlsSecs as Number = -100;   // when controls were last revealed
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
        if (_awakeArmed && (Time.now().value() - _armSecs) > 5) { _awakeArmed = false; }
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
        var vc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        var label = (_alarm != null) ? AlarmStore.label(_alarm) : "Alarm";
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var atMax = snoozeExhausted();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 52, Graphics.FONT_MEDIUM, label, vc);
        dc.drawText(_cx, _cy - 14, Graphics.FONT_LARGE, Fmt.time12(now.hour, now.min), vc);

        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var left = maxSn() - snoozeCount();
        var info = atMax
            ? "No snoozes left"
            : (left.format("%d") + (left == 1 ? " snooze left" : " snoozes left"));
        dc.drawText(_cx, _cy + 22, Graphics.FONT_XTINY, info, vc);

        // Controls stay hidden until a button is pressed, so the alarm just rings.
        if (controlsVisible()) {
            var msg = _awakeArmed ? "Press UP: I'm Awake!" : "Press BACK and then UP: I'm Awake!";
            var lines = ChoiceView.wrap(dc, msg, Graphics.FONT_XTINY, _w * 62 / 100);
            var ly = _h * 74 / 100;
            dc.setColor(_awakeArmed ? UI_GREEN : 0xCCCCCC, Graphics.COLOR_TRANSPARENT);
            for (var i = 0; i < lines.size() && i < 2; i++) {
                dc.drawText(_cx, ly + i * 18, Graphics.FONT_XTINY, lines[i], vc);
            }

            if (!atMax) { Ui.at(dc, _w, _h, UI_DEG_START, UI_RED, "Snooze"); }
            Ui.at(dc, _w, _h, UI_DEG_BACK, UI_GREEN, "BACK");
            Ui.at(dc, _w, _h, UI_DEG_UP, UI_GREEN, "UP");
        }
    }

    // ── State ────────────────────────────────────────────────────────────────

    function snoozeCount() as Number {
        var id = AlarmStore.ringingId();
        return (id != null) ? AlarmStore.snoozeCount(id) : 0;
    }
    function maxSn() as Number {
        return (_alarm != null) ? AlarmStore.maxSnoozeOf(_alarm) : DEFAULT_MAX_SNOOZE;
    }
    function snLen() as Number {
        return (_alarm != null) ? AlarmStore.snoozeLen(_alarm) : DEFAULT_SNOOZE_MINUTES;
    }
    function snoozeExhausted() as Boolean { return snoozeCount() >= maxSn(); }

    // Controls appear for a few seconds after any button press.
    function revealControls() as Void {
        _controlsSecs = Time.now().value();
        WatchUi.requestUpdate();
    }
    function controlsVisible() as Boolean {
        return (Time.now().value() - _controlsSecs) <= 8;
    }

    function armAwake() as Void {
        _awakeArmed = true;
        _armSecs = Time.now().value();
        revealControls();
    }
    function awakeReady() as Boolean {
        return _awakeArmed && (Time.now().value() - _armSecs) <= 5;
    }

    function stopTimer() as Void {
        if (_timer != null) { _timer.stop(); _timer = null; }
    }

    // ── Actions ──────────────────────────────────────────────────────────────

    function doSnooze() as Void {
        var id = AlarmStore.ringingId();
        if (id == null) { close(); return; }
        if (snoozeExhausted()) { return; }        // must use I'm Awake instead
        AlarmStore.incSnooze(id);
        var until = Time.now().value() + snLen() * 60;
        AlarmStore.scheduleSnooze(id, until);
        AlarmStore.setRinging(null);
        close();
    }

    function doAwake() as Void {
        var id = AlarmStore.ringingId();
        if (id != null) {
            AlarmStore.markFired(id);
            // A one-time ("Once") alarm has done its job - switch it off so the
            // list shows OFF afterwards.
            var found = AlarmStore.findById(id);
            if (found[1] != null && AlarmStore.days(found[1] as Dictionary) == 0) {
                AlarmStore.disableById(id);
            }
        }
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

    // First press just reveals the controls; a second START then snoozes.
    function onSelect() as Boolean {
        if (_view.controlsVisible()) {
            _view.doSnooze();
        } else {
            _view.revealControls();
        }
        return true;
    }

    // BACK arms "I'm Awake" (and reveals controls); UP completes it.
    function onBack() as Boolean { _view.armAwake(); return true; }
    function onPreviousPage() as Boolean {
        if (_view.awakeReady()) {
            _view.doAwake();
        } else {
            _view.revealControls();
        }
        return true;
    }

    // Everything else just reveals the controls and keeps it ringing.
    function onNextPage() as Boolean { _view.revealControls(); return true; }
    function onTap(evt as WatchUi.ClickEvent) as Boolean { _view.revealControls(); return true; }
}
