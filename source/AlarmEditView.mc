// AlarmEditView.mc
// Edits one alarm, one field at a time (no overlap). Works on a COPY of the
// alarm: nothing is written to storage until you choose "Save and Close" (or
// press START on that row). BACK or LIGHT cancels and discards — so backing out
// never silently creates or enables an alarm.

import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class AlarmEditView extends WatchUi.View {

    public var alarm as Dictionary;     // working copy
    public var index as Number;         // stored index (-1 for a new alarm)
    public var isNew as Boolean;

    private var _sel as Number = 0;
    private var _w as Number = 260;
    private var _h as Number = 260;
    private var _cx as Number = 130;
    private var _cy as Number = 130;

    function initialize(idx as Number, workingCopy as Dictionary, brandNew as Boolean) {
        View.initialize();
        index = idx;
        alarm = workingCopy;
        isNew = brandNew;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    // Rows: [key, title, value]. Wake/sleep window only shows for Sleep alarms;
    // Delete only shows for an existing alarm.
    function rows() as Array {
        var r = [];
        r.add(["time",  "Time",              Fmt.time12(AlarmStore.hour(alarm), AlarmStore.minute(alarm))]);
        r.add(["days",  "Scheduled Days",    Fmt.days(AlarmStore.days(alarm))]);
        r.add(["label", "Label",             AlarmStore.label(alarm)]);
        r.add(["type",  "Type",              Fmt.typeName(AlarmStore.type(alarm))]);
        if (AlarmStore.type(alarm) == TYPE_SLEEP) {
            r.add(["win", "Sleep Cycle Window", AlarmStore.window(alarm).format("%d") + " Minutes"]);
        }
        r.add(["mode",  "Alert",             Fmt.modeName(AlarmStore.mode(alarm))]);
        r.add(["on",    "Enabled",           AlarmStore.isOn(alarm) ? "Yes" : "No"]);
        r.add(["save",  "Save and Close",    ""]);
        if (!isNew) {
            r.add(["del", "Delete Alarm",    ""]);
        }
        return r;
    }

    function selected() as Number { return _sel; }
    function selectedKey() as String {
        var r = rows();
        if (_sel >= r.size()) { _sel = r.size() - 1; }
        return (r[_sel] as Array)[0] as String;
    }

    function moveDown() as Void { _sel = (_sel + 1) % rows().size(); WatchUi.requestUpdate(); }
    function moveUp() as Void {
        var n = rows().size();
        _sel = (_sel + n - 1) % n;
        WatchUi.requestUpdate();
    }

    // Write the working copy to storage.
    function commit() as Void {
        if (AlarmStore.days(alarm) == 0) {
            alarm.put("fireAt",
                AlarmStore.nextOccurrence(AlarmStore.hour(alarm), AlarmStore.minute(alarm)));
        }
        if (isNew) {
            AlarmStore.addAlarm(alarm);
        } else {
            AlarmStore.updateAlarm(index, alarm);
        }
        SmartAlarmApp.syncBackground();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var r = rows();
        if (_sel >= r.size()) { _sel = r.size() - 1; }
        var row = r[_sel] as Array;
        var key = row[0] as String;
        var title = row[1] as String;
        var value = row[2] as String;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Context: the alarm time
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h * 12 / 100, Graphics.FONT_XTINY,
                    Fmt.time12(AlarmStore.hour(alarm), AlarmStore.minute(alarm)),
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Field title
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 26, Graphics.FONT_MEDIUM, title, Graphics.TEXT_JUSTIFY_CENTER);

        // Field value
        if (value.length() > 0) {
            dc.setColor(0xCCCCCC, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy + 12, Graphics.FONT_SMALL, value, Graphics.TEXT_JUSTIFY_CENTER);
        }

        // Position
        dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h * 70 / 100, Graphics.FONT_XTINY,
                    (_sel + 1).format("%d") + " / " + r.size().format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Button hints (green action depends on the row)
        var green = "Change";
        if (key.equals("save")) { green = "Save"; }
        else if (key.equals("del")) { green = "Delete"; }
        else if (key.equals("on")) { green = "Toggle"; }
        Ui.hints(dc, _w, _h, green, "Cancel");
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

    // BACK cancels (discard).
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    // LIGHT also cancels.
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        if (evt.getKey() == WatchUi.KEY_LIGHT) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return true;
        }
        return false;
    }

    private function _activate() as Void {
        var key = _view.selectedKey();
        var a = _view.alarm;

        if (key.equals("time")) {
            var tp = new TimePickerView(a);
            WatchUi.pushView(tp, new TimePickerDelegate(tp), WatchUi.SLIDE_LEFT);

        } else if (key.equals("days")) {
            var dp = new DaysPicker(a);
            WatchUi.pushView(dp, new DaysPickerDelegate(dp), WatchUi.SLIDE_LEFT);

        } else if (key.equals("label")) {
            _pushChoice("Label", "label", _labelOptions(), AlarmStore.label(a), a);

        } else if (key.equals("type")) {
            _pushChoice("Type", "type", _typeOptions(), AlarmStore.type(a), a);

        } else if (key.equals("win")) {
            _pushChoice("Sleep Cycle Window", "win", _windowOptions(), AlarmStore.window(a), a);

        } else if (key.equals("mode")) {
            _pushChoice("Alert", "mode", _modeOptions(), AlarmStore.mode(a), a);

        } else if (key.equals("on")) {
            a.put("on", !AlarmStore.isOn(a));
            WatchUi.requestUpdate();

        } else if (key.equals("save")) {
            _view.commit();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);

        } else if (key.equals("del")) {
            AlarmStore.deleteAlarm(_view.index);
            SmartAlarmApp.syncBackground();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }

    private function _pushChoice(title as String, key as String, options as Array,
                                 current, a as Dictionary) as Void {
        var cv = new ChoiceView(title, key, options, current, a);
        WatchUi.pushView(cv, new ChoiceDelegate(cv), WatchUi.SLIDE_LEFT);
    }

    private function _typeOptions() as Array {
        return [
            [TYPE_SLEEP, "Sleep",
             "Wakes you during light sleep in the window before your set time, so you feel less groggy."],
            [TYPE_REMINDER, "Reminder",
             "Rings exactly at the set time. Use for reminders, not for waking from sleep."]
        ];
    }

    private function _windowOptions() as Array {
        var d = "How long before the set time the app watches your sleep to find a light moment to wake you.";
        return [
            [15, "15 Minutes", d],
            [30, "30 Minutes", d],
            [45, "45 Minutes", d],
            [60, "60 Minutes", d]
        ];
    }

    private function _modeOptions() as Array {
        return [
            [MODE_BOTH,  "Sound + Vibrate", ""],
            [MODE_SOUND, "Sound only",      ""],
            [MODE_VIBE,  "Vibrate only",    ""]
        ];
    }

    private function _labelOptions() as Array {
        var names = ["Wake up", "Work", "Gym", "Medication",
                     "Meeting", "Study", "Nap", "Reminder"];
        var out = [];
        for (var i = 0; i < names.size(); i++) {
            out.add([names[i], names[i], ""]);
        }
        return out;
    }
}
