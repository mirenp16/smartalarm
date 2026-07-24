// TimePicker.mc
// Sets an alarm time in three clear steps: hour -> minute -> AM/PM.
//   UP/DOWN : change the highlighted field
//   START   : go to the next field; on AM/PM it confirms and returns
//   BACK / LIGHT : step back a field (minute -> hour); on hour it exits
//
// AM/PM is its own field on its own line, so it never overlaps the digits.
// Writes into the working alarm Dictionary (the editor saves on close).

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class TimePickerView extends WatchUi.View {

    private var _alarm as Dictionary;
    private var _focus as Number = 0;   // 0 hour, 1 minute, 2 AM/PM
    private var _hour12 as Number;      // 1..12
    private var _min as Number;
    private var _pm as Boolean;
    private var _w as Number = 260;
    private var _h as Number = 260;
    private var _cx as Number = 130;
    private var _cy as Number = 130;

    function initialize(alarm as Dictionary) {
        View.initialize();
        _alarm = alarm;
        var h24 = AlarmStore.hour(alarm);
        _min = AlarmStore.minute(alarm);
        _pm = (h24 >= 12);
        var h = h24 % 12;
        _hour12 = (h == 0) ? 12 : h;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h * 14 / 100, Graphics.FONT_XTINY, "SET TIME",
                    Graphics.TEXT_JUSTIFY_CENTER);

        var numY = _cy - 30;
        // Hour
        dc.setColor((_focus == 0) ? Graphics.COLOR_WHITE : 0x666666, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx - 34, numY, Graphics.FONT_NUMBER_HOT, _hour12.format("%d"),
                    Graphics.TEXT_JUSTIFY_RIGHT);
        // Colon
        dc.setColor(0x999999, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, numY, Graphics.FONT_NUMBER_HOT, ":", Graphics.TEXT_JUSTIFY_CENTER);
        // Minute
        dc.setColor((_focus == 1) ? Graphics.COLOR_WHITE : 0x666666, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx + 34, numY, Graphics.FONT_NUMBER_HOT, _min.format("%02d"),
                    Graphics.TEXT_JUSTIFY_LEFT);

        // AM/PM on its own line
        dc.setColor((_focus == 2) ? Graphics.COLOR_WHITE : 0x666666, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + 38, Graphics.FONT_MEDIUM, _pm ? "PM" : "AM",
                    Graphics.TEXT_JUSTIFY_CENTER);

        var green = (_focus == 2) ? "Confirm" : "Next";
        Ui.hints(dc, _w, _h, green, "Back");
    }

    function bump(delta as Number) as Void {
        if (_focus == 0) {
            _hour12 = ((_hour12 - 1 + delta + 12) % 12) + 1;
        } else if (_focus == 1) {
            _min = (_min + 60 + delta) % 60;
        } else {
            _pm = !_pm;
        }
        WatchUi.requestUpdate();
    }

    // START: advance a field, or confirm on the last one. Returns true on confirm.
    function advance() as Boolean {
        if (_focus < 2) {
            _focus++;
            WatchUi.requestUpdate();
            return false;
        }
        var h24 = (_hour12 % 12) + (_pm ? 12 : 0);
        _alarm.put("h", h24);
        _alarm.put("m", _min);
        return true;
    }

    // BACK: step back a field. Returns true if we should exit the picker.
    function back() as Boolean {
        if (_focus > 0) {
            _focus--;
            WatchUi.requestUpdate();
            return false;
        }
        return true;
    }
}

class TimePickerDelegate extends WatchUi.BehaviorDelegate {

    private var _view as TimePickerView;

    function initialize(view as TimePickerView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onPreviousPage() as Boolean { _view.bump(1); return true; }   // UP
    function onNextPage() as Boolean { _view.bump(-1); return true; }      // DOWN

    function onSelect() as Boolean {
        if (_view.advance()) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }

    function onBack() as Boolean {
        if (_view.back()) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_LIGHT) {
            if (_view.back()) {
                WatchUi.popView(WatchUi.SLIDE_RIGHT);
            }
            return true;
        }
        return false;
    }
}
