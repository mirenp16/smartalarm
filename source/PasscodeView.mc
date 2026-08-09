// PasscodeView.mc
// Four-digit code entry, using the same one-digit-at-a-time mechanism as the
// time picker: UP/DOWN change the highlighted digit, START moves to the next
// digit and submits on the last one.
//
// Modes:
//   PC_MODE_ENTER - unlock (exit Active Alarm Mode / dismiss a ringing alarm)
//   PC_MODE_SET   - choose a new code (Passcode Setup)
//
// IMPORTANT ordering rule: the delegate closes this screen FIRST and only then
// runs the callback. Doing it the other way round meant the callback's
// switchToView replaced *this* view, and the following popView then undid it -
// which is why entering a correct code appeared to do nothing.
//
// After PASSCODE_MAX_TRIES wrong attempts the master code is filled in and shown
// on screen, so a half-asleep user can simply press START to get out. The code is
// stored in plain text on purpose: this is friction to wake you, not security.

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

const PC_MODE_ENTER = 0;
const PC_MODE_SET   = 1;

// advance() results
const PC_CONTINUE = 0;   // stay on screen (more digits, or wrong code)
const PC_DONE     = 1;   // accepted / saved - close and run the callback

class PasscodeView extends WatchUi.View {

    private var _digits as Array<Number> = [0, 0, 0, 0];
    private var _pos as Number = 0;
    private var _mode as Number;
    private var _tries as Number = 0;
    private var _error as Boolean = false;
    private var _savedCode as String = "";     // shown after a successful SET
    private var _w as Number = 360;
    private var _h as Number = 360;
    private var _cx as Number = 180;
    private var _cy as Number = 180;

    public var onOk as Method?;   // run by the delegate AFTER this view closes

    function initialize(mode as Number, callback as Method?) {
        View.initialize();
        _mode = mode;
        onOk = callback;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var vc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var exhausted = (_tries >= PASSCODE_MAX_TRIES);

        // Title
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        var title = (_mode == PC_MODE_SET) ? "Set Passcode" : "Enter Passcode";
        dc.drawText(_cx, _h * 13 / 100, Graphics.FONT_XTINY, title, vc);

        // The four digits; the active one is white with an underline well clear
        // of the glyph (it used to sit on top of the digit).
        var spacing = 42;
        var startX = _cx - (spacing * 3) / 2;
        var digitsY = exhausted ? (_cy - 44) : (_cy - 30);
        for (var i = 0; i < 4; i++) {
            var focused = (i == _pos);
            dc.setColor(focused ? Graphics.COLOR_WHITE : 0x666666, Graphics.COLOR_TRANSPARENT);
            dc.drawText(startX + i * spacing, digitsY, Graphics.FONT_NUMBER_MEDIUM,
                        _digits[i].format("%d"), vc);
            if (focused) {
                dc.setPenWidth(3);
                var uy = digitsY + 30;          // clear gap below the digit
                dc.drawLine(startX + i * spacing - 13, uy,
                            startX + i * spacing + 13, uy);
                dc.setPenWidth(1);
            }
        }

        // Text block starts well below the underline.
        if (_error) {
            dc.setColor(UI_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy + 30, Graphics.FONT_XTINY, "Wrong Code!", vc);
            dc.drawText(_cx, _cy + 52, Graphics.FONT_XTINY, "Please Try Again!", vc);

        } else if (exhausted) {
            dc.setColor(UI_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy + 16, Graphics.FONT_XTINY, "5 Wrong Attempts!", vc);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy + 42, Graphics.FONT_XTINY,
                        "Master: " + MASTER_PASSCODE, vc);
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy + 68, Graphics.FONT_XTINY, "Press Start to Exit", vc);

        } else if (_mode == PC_MODE_SET) {
            if (_savedCode.length() > 0) {
                // Confirmation of the code just saved, in green, over two lines.
                dc.setColor(UI_GREEN, Graphics.COLOR_TRANSPARENT);
                dc.drawText(_cx, _cy + 30, Graphics.FONT_XTINY, "New Passcode Set!", vc);
                dc.drawText(_cx, _cy + 52, Graphics.FONT_SMALL, _savedCode, vc);
            } else {
                dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
                dc.drawText(_cx, _cy + 30, Graphics.FONT_XTINY,
                            "Current: " + AlarmStore.passcode(), vc);
                dc.drawText(_cx, _cy + 52, Graphics.FONT_XTINY,
                            "Master: " + MASTER_PASSCODE, vc);
            }
        }

        Ui.start(dc, _w, _h, (_pos == 3) ? "OK" : "Next");
        // Setup can always be abandoned; entry cannot.
        if (_mode == PC_MODE_SET) {
            Ui.back(dc, _w, _h, "Back");
        }
    }

    // ── Input ────────────────────────────────────────────────────────────────

    function bump(delta as Number) as Void {
        _digits[_pos] = (_digits[_pos] + 10 + delta) % 10;
        _error = false;
        _savedCode = "";
        WatchUi.requestUpdate();
    }

    function code() as String {
        return _digits[0].format("%d") + _digits[1].format("%d")
             + _digits[2].format("%d") + _digits[3].format("%d");
    }

    // START: next digit, or submit on the last one.
    function advance() as Number {
        if (_pos < 3) {
            _pos++;
            WatchUi.requestUpdate();
            return PC_CONTINUE;
        }

        if (_mode == PC_MODE_SET) {
            _savedCode = code();
            AlarmStore.setPasscode(_savedCode);
            WatchUi.requestUpdate();
            return PC_DONE;
        }

        if (AlarmStore.checkPasscode(code())) {
            return PC_DONE;
        }

        // Wrong code.
        _tries++;
        _error = true;
        _pos = 0;
        if (_tries >= PASSCODE_MAX_TRIES) {
            // Fill in the master code and tell the user, so they can just press START.
            setDigits(MASTER_PASSCODE);
            _error = false;
            _pos = 3;
        }
        WatchUi.requestUpdate();
        return PC_CONTINUE;
    }

    private function setDigits(s as String) as Void {
        var chars = s.toCharArray();
        for (var i = 0; i < 4 && i < chars.size(); i++) {
            _digits[i] = (chars[i].toString()).toNumber();
        }
    }

    // Step back a digit; returns true if the screen should close.
    function back() as Boolean {
        // In Setup, BACK always leaves straight away - it used to walk back through
        // all four digits, which is why it took several presses to get out.
        if (_mode == PC_MODE_SET) { return true; }
        if (_pos > 0) {
            _pos--;
            _error = false;
            WatchUi.requestUpdate();
            return false;
        }
        // In ENTER mode BACK can't escape - that would defeat the point.
        return false;
    }

    function isSetMode() as Boolean { return _mode == PC_MODE_SET; }
    function isSaved() as Boolean { return _savedCode.length() > 0; }
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
        // In Setup, once the code is saved the confirmation is showing - a second
        // START closes the screen (previously nothing happened here).
        if (_view.isSetMode() && _view.isSaved()) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            return true;
        }

        if (_view.advance() == PC_DONE) {
            // In SET mode stay put so the user can read the confirmation; the
            // next START (handled above) closes it.
            if (_view.isSetMode()) {
                return true;
            }
            // Close FIRST, then run the callback (see the note at the top).
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            var cb = _view.onOk;
            if (cb != null) { cb.invoke(); }
        }
        return true;
    }

    function onBack() as Boolean {
        if (_view.back()) {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
        return true;
    }

    // Touch ignored so a palm/stray touch can't interfere.
    function onTap(evt as WatchUi.ClickEvent) as Boolean { return true; }
    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean { return true; }
}
