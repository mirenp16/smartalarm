// AlarmEditView.mc
// Edits one sleep-cycle alarm, one field at a time. Works on a COPY: nothing is
// saved until "Save and Close". BACK cancels and discards. Saving an ENABLED alarm
// drops you straight into Active Alarm mode.

import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class AlarmEditView extends WatchUi.View {

    public var alarm as Dictionary;
    public var index as Number;
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

    function rows() as Array {
        var r = [];
        r.add(["time",  "Time",               Fmt.time12(AlarmStore.hour(alarm), AlarmStore.minute(alarm))]);
        r.add(["days",  "Scheduled Days",     Fmt.days(AlarmStore.days(alarm))]);
        r.add(["label", "Label",              AlarmStore.label(alarm)]);
        r.add(["win",   "Sleep Cycle Window", AlarmStore.window(alarm).format("%d") + " Minutes"]);
        r.add(["mode",  "Alert",              Fmt.modeName(AlarmStore.mode(alarm))]);
        r.add(["on",    "State",              AlarmStore.isOn(alarm) ? "Enabled" : "Disabled"]);
        r.add(["save",  "Save and Close",     ""]);
        if (!isNew) {
            r.add(["del", "Delete Alarm",     ""]);
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
        // Re-arm: clear any leftover "fired" flag so an edited alarm goes off again.
        AlarmStore.clearFired(AlarmStore.id(alarm));
        SmartAlarmApp.syncBackground();
    }

    function isEnabled() as Boolean { return AlarmStore.isOn(alarm); }

    function onUpdate(dc as Graphics.Dc) as Void {
        var r = rows();
        if (_sel >= r.size()) { _sel = r.size() - 1; }
        var row = r[_sel] as Array;
        var key = row[0] as String;
        var title = row[1] as String;
        var value = row[2] as String;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h * 12 / 100, Graphics.FONT_XTINY,
                    Fmt.time12(AlarmStore.hour(alarm), AlarmStore.minute(alarm)),
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Title (FONT_SMALL so long labels like "Sleep Cycle Window" fit).
        // Vertically centred with a clear gap so title and value never overlap.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 26, Graphics.FONT_SMALL, title,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        if (value.length() > 0) {
            dc.setColor(0xCCCCCC, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy + 16, Graphics.FONT_SMALL, value,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        dc.setColor(0x666666, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h * 72 / 100, Graphics.FONT_XTINY,
                    (_sel + 1).format("%d") + " / " + r.size().format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER);

        var green = "Change";
        if (key.equals("save")) { green = "Save"; }
        else if (key.equals("del")) { green = "Delete"; }
        else if (key.equals("on")) { green = "Toggle"; }
        Ui.start(dc, _w, _h, green);
        Ui.back(dc, _w, _h, "Cancel");
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
            if (_view.isEnabled()) {
                var bv = new BedsideView();
                WatchUi.switchToView(bv, new BedsideDelegate(bv), WatchUi.SLIDE_UP);
            }

        } else if (key.equals("del")) {
            var dialog = new WatchUi.Confirmation("Delete this alarm?");
            WatchUi.pushView(dialog, new DeleteConfirmDelegate(_view.index), WatchUi.SLIDE_UP);
        }
    }

    private function _pushChoice(title as String, key as String, options as Array,
                                 current, a as Dictionary) as Void {
        var cv = new ChoiceView(title, key, options, current, a);
        WatchUi.pushView(cv, new ChoiceDelegate(cv), WatchUi.SLIDE_LEFT);
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

// Confirms deleting an alarm, then closes the editor.
class DeleteConfirmDelegate extends WatchUi.ConfirmationDelegate {

    private var _index as Number;

    function initialize(index as Number) {
        ConfirmationDelegate.initialize();
        _index = index;
    }

    function onResponse(response) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            AlarmStore.deleteAlarm(_index);
            SmartAlarmApp.syncBackground();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);   // close the editor
        }
        return true;
    }
}
