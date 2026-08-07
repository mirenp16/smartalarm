// PasscodeView.mc
// Four-digit code entry, using the same one-digit-at-a-time mechanism as the
// time picker: UP/DOWN change the highlighted digit, START moves to the next
// digit and confirms on the last one.
//
// Two modes:
//   PC_MODE_ENTER - unlock (exit Active Alarm Mode / dismiss a ringing alarm)
//   PC_MODE_SET   - choose a new code (Passcode Setup)
//
// After PASSCODE_MAX_TRIES wrong attempts the digits are pre-filled with the
// master code so a half-asleep user can simply press START to get out.
// This is deliberate friction, not security - the code is stored in plain text.

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

const PC_MODE_ENTER = 0;
const PC_MODE_SET   = 1;

class PasscodeView extends WatchUi.View {

    // Typed so the compiler knows these are Numbers (silences container warnings).
    private var _digits as Array<Number> = [0, 0, 0, 0];
    private var _pos as Number = 0;
    private var _mode as Number;
    private var _tries as Number = 0;
    private var _error as Boolean = false;
    private var _onOk as Method?;          // called when the code is accepted / set
    private var _w as Number = 260;
    private var _h as Number = 260;
    private var _cx as Number = 130;
    private var _cy as Number = 130;

    // onOk is invoked with no arguments once the code is accepted (ENTER) or
    // saved (SET). It is responsible for whatever should happen next.
    function initialize(mode as Number, onOk as Method?) {
        View.initialize();
        _mode = mode;
        _onOk = onOk;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var vc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Title
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var title = (_mode == PC_MODE_SET) ? "Set Passcode" : "Enter Passcode";
        dc.drawText(_cx, _h * 16 / 100, Graphics.FONT_XTINY, title, vc);

        // The four digits, spaced out; the active one is white, the rest dim.
        var spacing = 44;
        var startX = _cx - (spacing * 3) / 2;
        for (var i = 0; i < 4; i++) {
            var focused = (i == _pos);
            dc.setColor(focused ? Graphics.COLOR_WHITE : 0x666666, Graphics.COLOR_TRANSPARENT);
            dc.drawText(startX + i * spacing, _cy - 14, Graphics.FONT_NUMBER_MEDIUM,
                        _digits[i].format("%d"), vc);
            // underline the active digit
            if (focused) {
                dc.setPenWidth(3);
                dc.drawLine(startX + i * spacing - 14, _cy + 16,
                            startX + i * spacing + 14, _cy + 16);
                dc.setPenWidth(1);
            }
        }

        // Wrong-code message, in red, on two lines.
        if (_error) {
            dc.setColor(UI_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy + 44, Graphics.FONT_XTINY, "Wrong Code!", vc);
            dc.drawText(_cx, _cy + 64, Graphics.FONT_XTINY, "Please Try Again!", vc);
        } else if (_tries >= PASSCODE_MAX_TRIES) {
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy + 50, Graphics.FONT_XTINY, "Master code filled in", vc);
        }

        Ui.start(dc, _w, _h, (_pos == 3) ? "OK" : "Next");
    }

    // ── Input ────────────────────────────────────────────────────────────────

    function bump(delta as Number) as Void {
        _digits[_pos] = (_digits[_pos] + 10 + delta) % 10;
        _error = false;
        WatchUi.requestUpdate();
    }

    function code() as String {
        return _digits[0].format("%d") + _digits[1].format("%d")
             + _digits[2].format("%d") + _digits[3].format("%d");
    }

    // START: next digit, or submit on the last one.
    // Returns true when the screen should close.
    function advance() as Boolean {
        if (_pos < 3) {
            _pos++;
            WatchUi.requestUpdate();
            return false;
        }

        if (_mode == PC_MODE_SET) {
            AlarmStore.setPasscode(code());
            fireOk();
            return true;
        }

        if (AlarmStore.checkPasscode(code())) {
            fireOk();
            return true;
        }

        // Wrong code
        _tries++;
        _error = true;
        _pos = 0;
        if (_tries >= PASSCODE_MAX_TRIES) {
            // Pre-fill the master code so the user can just confirm.
            _digits = [0, 0, 0, 0] as Array<Number>;
            _error = false;
        }
        WatchUi.requestUpdate();
        return false;
    }

    // Step back a digit; returns true if the screen should close.
    function back() as Boolean {
        if (_pos > 0) {
            _pos--;
            _error = false;
            WatchUi.requestUpdate();
            return false;
        }
        // In ENTER mode you can't escape by pressing BACK - that would defeat
        // the point. Only SET mode can be cancelled.
        return (_mode == PC_MODE_SET);
    }

    private function fireOk() as Void {
        if (_onOk != null) {
            _onOk.invoke();
        }
    }
}

class PasscodeDelegate extends WatchUi.BehaviorDelegate {

    private var _view as PasscodeView;

    function initialize(view as PasscodeView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onPreviousPage() as Boolean { _view.bump(1); return true; }   // UP
    function onNextPage() as Boolean { _view.bump(-1); return true; }      // DOWN

    function onSelect() as Boolean {
        if (_view.advance()) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return true;
    }

    function onBack() as Boolean {
        if (_view.back()) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return true;
    }

    // Touch is ignored here so a palm/stray touch can't interfere.
    function onTap(evt as WatchUi.ClickEvent) as Boolean { return true; }
    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean { return true; }
}
