// AlarmEditView.mc
// Edits one alarm, showing ONE field at a time (title + value) so nothing
// overlaps. UP/DOWN move between fields; START/tap changes the highlighted field.
// Works on a live reference to the alarm Dictionary and persists every change.
//
// The Wake Window field only appears for Sleep alarms. Setting no days makes the
// alarm one-time; persist() then computes its next fire time.

import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class AlarmEditView extends WatchUi.View {

    public var alarm as Dictionary;
    public var index as Number;

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

    // Rows: each is [key, title, value]. Wake Window only shows for Sleep alarms.
    function rows() as Array {
        var r = [];
        r.add(["time",  "Time",         Fmt.time12(AlarmStore.hour(alarm), AlarmStore.minute(alarm))]);
        r.add(["days",  "Days",         Fmt.days(AlarmStore.days(alarm))]);
        r.add(["label", "Label",        AlarmStore.label(alarm)]);
        r.add(["type",  "Type",         Fmt.typeName(AlarmStore.type(alarm))]);
        if (AlarmStore.type(alarm) == TYPE_SLEEP) {
            r.add(["win", "Wake Window", AlarmStore.window(alarm).format("%d") + " min"]);
        }
        r.add(["mode",  "Alert",        Fmt.modeName(AlarmStore.mode(alarm))]);
        r.add(["on",    "Enabled",      AlarmStore.isOn(alarm) ? "On" : "Off"]);
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

    // Persist the working copy. For one-time alarms (no days) compute the next
    // time it should fire.
    function persist() as Void {
        if (AlarmStore.days(alarm) == 0) {
            alarm.put("fireAt",
                AlarmStore.nextOccurrence(AlarmStore.hour(alarm), AlarmStore.minute(alarm)));
        }
        AlarmStore.updateAlarm(index, alarm);
        SmartAlarmApp.syncBackground();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var r = rows();
        if (_sel >= r.size()) { _sel = r.size() - 1; }
        var row = r[_sel] as Array;
        var title = row[1] as String;
        var value = row[2] as String;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Context header: the alarm time
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h * 12 / 100, Graphics.FONT_XTINY,
                    Fmt.time12(AlarmStore.hour(alarm), AlarmStore.minute(alarm)),
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Field title (big)
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 26, Graphics.FONT_MEDIUM, title, Graphics.TEXT_JUSTIFY_CENTER);

        // Field value
        if (value.length() > 0) {
            dc.setColor(0xCCCCCC, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy + 12, Graphics.FONT_SMALL, value, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Position + hint
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h - 30, Graphics.FONT_XTINY,
                    (_sel + 1).format("%d") + " / " + r.size().format("%d") + "   START",
                    Graphics.TEXT_JUSTIFY_CENTER);
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
