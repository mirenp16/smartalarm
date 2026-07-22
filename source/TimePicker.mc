// TimePicker.mc
// A custom hour + minute picker. UP/DOWN change the focused field; START moves
// hour -> minute -> confirm. Writes straight into the alarm Dictionary.

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class TimePickerView extends WatchUi.View {

    private var _alarm as Dictionary;
    private var _focus as Number = 0;   // 0 hour, 1 minute, 2 confirm
    private var _hour as Number;
    private var _min as Number;
    private var _w as Number = 260;
    private var _h as Number = 260;
    private var _cx as Number = 130;
    private var _cy as Number = 130;

    function initialize(alarm as Dictionary) {
        View.initialize();
        _alarm = alarm;
        _hour = AlarmStore.hour(alarm);
        _min = AlarmStore.minute(alarm);
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, 20, Graphics.FONT_XTINY, "SET TIME", Graphics.TEXT_JUSTIFY_CENTER);

        var dh = _hour % 12;
        if (dh == 0) { dh = 12; }

        // Hour
        dc.setColor((_focus == 0) ? 0x00CC66 : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx - 36, _cy - 34, Graphics.FONT_NUMBER_HOT, dh.format("%d"),
                    Graphics.TEXT_JUSTIFY_RIGHT);

        // Colon
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 34, Graphics.FONT_NUMBER_HOT, ":", Graphics.TEXT_JUSTIFY_CENTER);

        // Minute
        dc.setColor((_focus == 1) ? 0x00CC66 : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx + 36, _cy - 34, Graphics.FONT_NUMBER_HOT, _min.format("%02d"),
                    Graphics.TEXT_JUSTIFY_LEFT);

        // AM/PM
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + 26, Graphics.FONT_SMALL, Fmt.ampm(_hour),
                    Graphics.TEXT_JUSTIFY_CENTER);

        var hints = ["UP/DOWN: hour", "UP/DOWN: minute", "START to confirm"];
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h - 40, Graphics.FONT_XTINY, hints[_focus], Graphics.TEXT_JUSTIFY_CENTER);

        if (_focus == 2) {
            dc.setColor(0x00CC66, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _h - 24, Graphics.FONT_XTINY, "[ CONFIRM ]", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function bump(delta as Number) as Void {
        if (_focus == 0) {
            _hour = (_hour + 24 + delta) % 24;
        } else if (_focus == 1) {
            _min = (_min + 60 + delta) % 60;
        }
        WatchUi.requestUpdate();
    }

    // Advance focus; returns true when the user confirms.
    function advance() as Boolean {
        if (_focus < 2) {
            _focus++;
            WatchUi.requestUpdate();
            return false;
        }
        _alarm.put("h", _hour);
        _alarm.put("m", _min);
        return true;
    }
}

class TimePickerDelegate extends WatchUi.BehaviorDelegate {

    private var _view as TimePickerView;
    private var _edit as AlarmEditView;

    function initialize(view as TimePickerView, edit as AlarmEditView) {
        BehaviorDelegate.initialize();
        _view = view;
        _edit = edit;
    }

    function onNextPage() as Boolean { _view.bump(-1); return true; }   // DOWN
    function onPreviousPage() as Boolean { _view.bump(1); return true; } // UP

    function onSelect() as Boolean {
        if (_view.advance()) {
            _edit.persist();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
