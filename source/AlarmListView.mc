// AlarmListView.mc
// Home screen. Shows ONE item at a time (an alarm, "+ Add alarm", or "Settings").
// UP/DOWN move; START opens the item; LIGHT toggles the highlighted alarm on/off
// (red = it will turn off). Reads live from storage, so it's always current.

import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class AlarmListView extends WatchUi.View {

    private var _sel as Number = 0;
    private var _w as Number = 260;
    private var _h as Number = 260;
    private var _cx as Number = 130;
    private var _cy as Number = 130;

    function initialize() { View.initialize(); }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    // Slots = alarms + "Add" + "Bedside Mode" + "Settings"
    function slotCount() as Number { return AlarmStore.getAlarms().size() + 3; }
    function selected() as Number { return _sel; }
    function isAddSlot() as Boolean { return _sel == AlarmStore.getAlarms().size(); }
    function isBedsideSlot() as Boolean { return _sel == AlarmStore.getAlarms().size() + 1; }
    function isSettingsSlot() as Boolean { return _sel == AlarmStore.getAlarms().size() + 2; }

    function moveDown() as Void { _sel = (_sel + 1) % slotCount(); WatchUi.requestUpdate(); }
    function moveUp() as Void {
        var n = slotCount();
        _sel = (_sel + n - 1) % n;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var alarms = AlarmStore.getAlarms();
        var n = alarms.size() + 3;
        if (_sel >= n) { _sel = n - 1; }
        if (_sel < 0)  { _sel = 0; }

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h * 8 / 100, Graphics.FONT_XTINY, "SMART ALARM",
                    Graphics.TEXT_JUSTIFY_CENTER);

        var greenHint = "Open";
        var redHint = null;

        if (_sel == alarms.size()) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy - 12, Graphics.FONT_MEDIUM, "+ Add alarm",
                        Graphics.TEXT_JUSTIFY_CENTER);
        } else if (_sel == alarms.size() + 1) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy - 18, Graphics.FONT_MEDIUM, "Bedside Mode",
                        Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(0x999999, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy + 12, Graphics.FONT_XTINY, "Reliable on-time wake",
                        Graphics.TEXT_JUSTIFY_CENTER);
        } else if (_sel == alarms.size() + 2) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy - 12, Graphics.FONT_MEDIUM, "Settings",
                        Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            var a = alarms[_sel] as Dictionary;
            var on = AlarmStore.isOn(a);
            greenHint = "Edit";
            redHint = on ? "Turn off" : "Turn on";

            dc.setColor(on ? Graphics.COLOR_WHITE : 0x777777, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy - 46, Graphics.FONT_LARGE,
                        Fmt.time12(AlarmStore.hour(a), AlarmStore.minute(a)),
                        Graphics.TEXT_JUSTIFY_CENTER);

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy - 2, Graphics.FONT_SMALL, AlarmStore.label(a),
                        Graphics.TEXT_JUSTIFY_CENTER);

            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy + 22, Graphics.FONT_XTINY,
                        Fmt.days(AlarmStore.days(a)), Graphics.TEXT_JUSTIFY_CENTER);

            if (!on) {
                dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
                dc.drawText(_cx, _cy + 42, Graphics.FONT_XTINY, "OFF",
                            Graphics.TEXT_JUSTIFY_CENTER);
            }
        }

        dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h * 70 / 100, Graphics.FONT_XTINY,
                    (_sel + 1).format("%d") + " / " + n.format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER);

        Ui.hints(dc, _w, _h, greenHint, redHint);
    }

    // Toggle the highlighted alarm's enabled state (immediate).
    function toggleHighlighted() as Void {
        var alarms = AlarmStore.getAlarms();
        if (_sel < alarms.size()) {
            var a = alarms[_sel] as Dictionary;
            a.put("on", !AlarmStore.isOn(a));
            if (AlarmStore.days(a) == 0 && AlarmStore.isOn(a)) {
                a.put("fireAt", AlarmStore.nextOccurrence(AlarmStore.hour(a), AlarmStore.minute(a)));
            }
            AlarmStore.updateAlarm(_sel, a);
            SmartAlarmApp.syncBackground();
            WatchUi.requestUpdate();
        }
    }
}

class AlarmListDelegate extends WatchUi.BehaviorDelegate {

    private var _view as AlarmListView;

    function initialize(view as AlarmListView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean { _view.moveDown(); return true; }
    function onPreviousPage() as Boolean { _view.moveUp(); return true; }
    function onSelect() as Boolean { _open(); return true; }
    function onTap(evt as WatchUi.ClickEvent) as Boolean { _open(); return true; }

    // LIGHT toggles the highlighted alarm on/off.
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_LIGHT) {
            _view.toggleHighlighted();
            return true;
        }
        return false;
    }

    private function _open() as Void {
        if (_view.isAddSlot()) {
            var na = AlarmStore.newAlarm();
            var v = new AlarmEditView(-1, na, true);
            WatchUi.pushView(v, new AlarmEditDelegate(v), WatchUi.SLIDE_LEFT);
        } else if (_view.isBedsideSlot()) {
            var b = new BedsideView();
            WatchUi.pushView(b, new BedsideDelegate(b), WatchUi.SLIDE_UP);
        } else if (_view.isSettingsSlot()) {
            var s = new SettingsView();
            WatchUi.pushView(s, new SettingsDelegate(s), WatchUi.SLIDE_LEFT);
        } else {
            var sel = _view.selected();
            var a = AlarmStore.getAlarms()[sel] as Dictionary;
            var v = new AlarmEditView(sel, AlarmStore.clone(a), false);
            WatchUi.pushView(v, new AlarmEditDelegate(v), WatchUi.SLIDE_LEFT);
        }
    }
}
