// AlarmEditView.mc
// Edits a single alarm. Works on a live reference to the alarm Dictionary, so
// when a sub-picker changes a field the change is visible immediately. Every
// change is persisted to storage right away (so the background service always
// sees current settings even if the app is closed).
//
// Rows are built dynamically: the Wake Window row only appears for Sleep alarms.

import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class AlarmEditView extends WatchUi.View {

    public var alarm as Dictionary;      // live working copy (reference)
    public var index as Number;          // position in the stored list

    private var _sel as Number = 0;
    private var _w as Number = 260;
    private var _h as Number = 260;
    private var _cx as Number = 130;
    private var _cy as Number = 130;

    function initialize(idx as Number, a as Dictionary) {
        View.initialize();
        index = idx;
        alarm = a;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    // Builds the list of rows for the current alarm. Each row is [key, title, value].
    function rows() as Array {
        var r = [];
        r.add(["time",  "Time",       Fmt.time12(AlarmStore.hour(alarm), AlarmStore.minute(alarm))]);
        r.add(["days",  "Days",       Fmt.days(AlarmStore.days(alarm))]);
        r.add(["label", "Label",      AlarmStore.label(alarm)]);
        r.add(["type",  "Type",       Fmt.typeName(AlarmStore.type(alarm))]);
        if (AlarmStore.type(alarm) == TYPE_SLEEP) {
            r.add(["win", "Wake Window", AlarmStore.window(alarm).format("%d") + " min"]);
        }
        r.add(["mode",  "Alert",      Fmt.modeName(AlarmStore.mode(alarm))]);
        r.add(["on",    "Enabled",    AlarmStore.isOn(alarm) ? "On" : "Off"]);
        r.add(["save",  "Save & close", ""]);
        r.add(["del",   "Delete alarm", ""]);
        return r;
    }

    function selected() as Number { return _sel; }
    function selectedKey() as String {
        var r = rows();
        if (_sel >= r.size()) { _sel = r.size() - 1; }
        return (r[_sel] as Array)[0] as String;
    }

    function moveDown() as Void {
        _sel = (_sel + 1) % rows().size();
        WatchUi.requestUpdate();
    }
    function moveUp() as Void {
        var n = rows().size();
        _sel = (_sel + n - 1) % n;
        WatchUi.requestUpdate();
    }

    // Persist the working copy back to storage and keep background in sync.
    function persist() as Void {
        AlarmStore.updateAlarm(index, alarm);
        SmartAlarmApp.syncBackground();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var r = rows();
        if (_sel >= r.size()) { _sel = r.size() - 1; }

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Header shows the alarm time so you always know what you're editing.
        dc.setColor(0x00CC66, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, 12, Graphics.FONT_XTINY,
                    Fmt.time12(AlarmStore.hour(alarm), AlarmStore.minute(alarm)),
                    Graphics.TEXT_JUSTIFY_CENTER);

        // 3-row carousel of fields
        _drawField(dc, r, _sel - 1, _cy - 58, false);
        _drawField(dc, r, _sel,     _cy,      true);
        _drawField(dc, r, _sel + 1, _cy + 58, false);

        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h - 22, Graphics.FONT_XTINY, "START to change",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function _drawField(dc as Graphics.Dc, r as Array, i as Number,
                                y as Number, focused as Boolean) as Void {
        if (i < 0 || i >= r.size()) { return; }
        var row = r[i] as Array;
        var title = row[1] as String;
        var value = row[2] as String;

        var color = focused ? Graphics.COLOR_WHITE : 0x666666;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, y - (focused ? 12 : 0),
                    focused ? Graphics.FONT_SMALL : Graphics.FONT_XTINY,
                    title, Graphics.TEXT_JUSTIFY_CENTER);

        if (value.length() > 0) {
            dc.setColor(focused ? 0x00CC66 : 0x556655, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, y + (focused ? 14 : 0),
                        focused ? Graphics.FONT_TINY : Graphics.FONT_XTINY,
                        value, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}

class AlarmEditDelegate extends WatchUi.BehaviorDelegate {

    private var _view as AlarmEditView;

    function initialize(view as AlarmEditView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean { _view.moveDown(); return true; }
    function onPreviousPage() as Boolean { _view.moveUp(); return true; }

    function onSelect() as Boolean { _activate(); return true; }
    function onTap(evt as WatchUi.ClickEvent) as Boolean { _activate(); return true; }

    // Back always saves, then returns to the list.
    function onBack() as Boolean {
        _view.persist();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    private function _activate() as Void {
        var key = _view.selectedKey();
        var a = _view.alarm;

        if (key.equals("time")) {
            var tp = new TimePickerView(a);
            WatchUi.pushView(tp, new TimePickerDelegate(tp, _view), WatchUi.SLIDE_LEFT);

        } else if (key.equals("days")) {
            var dp = new DaysPicker(a, _view);
            WatchUi.pushView(dp, new DaysPickerDelegate(dp), WatchUi.SLIDE_LEFT);

        } else if (key.equals("label")) {
            var lp = new LabelPicker(a, _view);
            WatchUi.pushView(lp, new SimplePickerDelegate(lp), WatchUi.SLIDE_LEFT);

        } else if (key.equals("type")) {
            var yp = new TypePicker(a, _view);
            WatchUi.pushView(yp, new SimplePickerDelegate(yp), WatchUi.SLIDE_LEFT);

        } else if (key.equals("win")) {
            var wp = new WindowPicker(a, _view);
            WatchUi.pushView(wp, new SimplePickerDelegate(wp), WatchUi.SLIDE_LEFT);

        } else if (key.equals("mode")) {
            var mp = new ModePicker(a, _view);
            WatchUi.pushView(mp, new SimplePickerDelegate(mp), WatchUi.SLIDE_LEFT);

        } else if (key.equals("on")) {
            a.put("on", !AlarmStore.isOn(a));
            _view.persist();
            WatchUi.requestUpdate();

        } else if (key.equals("save")) {
            _view.persist();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);

        } else if (key.equals("del")) {
            AlarmStore.deleteAlarm(_view.index);
            SmartAlarmApp.syncBackground();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }
}
