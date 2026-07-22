// Pickers.mc
// The simple "choose one / toggle" screens used by the alarm editor. These use
// Garmin's built-in Menu2 / CheckboxMenu widgets, which automatically adapt to
// round and square screens and never overlap text.
//
// Each picker holds a live reference to the alarm Dictionary and the editor view,
// so a choice is written straight into the alarm and persisted.

import Toybox.Lang;
import Toybox.WatchUi;

// ── Base class for single-choice pickers ─────────────────────────────────────
// A subclass just adds its items; selecting an item writes item.getId() into the
// alarm field named `key`.
class FieldPicker extends WatchUi.Menu2 {

    public var alarm as Dictionary;
    public var edit as AlarmEditView;
    private var _key as String;

    function initialize(title as String, key as String,
                        a as Dictionary, e as AlarmEditView) {
        Menu2.initialize({:title => title});
        _key = key;
        alarm = a;
        edit = e;
    }

    function apply(item as WatchUi.MenuItem) as Void {
        alarm.put(_key, item.getId());
    }
}

class SimplePickerDelegate extends WatchUi.Menu2InputDelegate {

    private var _picker as FieldPicker;

    function initialize(picker as FieldPicker) {
        Menu2InputDelegate.initialize();
        _picker = picker;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        _picker.apply(item);
        _picker.edit.persist();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

// ── Label picker ─────────────────────────────────────────────────────────────
// Garmin watches have no keyboard, so we offer a curated preset list. (Free-text
// entry can be added later on devices that support it.)
class LabelPicker extends FieldPicker {
    function initialize(a as Dictionary, e as AlarmEditView) {
        FieldPicker.initialize("Label", "label", a, e);
        var presets = ["Wake up", "Work", "Gym", "Medication",
                       "Meeting", "Study", "Nap", "Reminder"];
        for (var i = 0; i < presets.size(); i++) {
            addItem(new WatchUi.MenuItem(presets[i], null, presets[i], null));
        }
    }
}

// ── Type picker ──────────────────────────────────────────────────────────────
class TypePicker extends FieldPicker {
    function initialize(a as Dictionary, e as AlarmEditView) {
        FieldPicker.initialize("Type", "type", a, e);
        addItem(new WatchUi.MenuItem("Sleep",
                "Smart wake in the window", TYPE_SLEEP, null));
        addItem(new WatchUi.MenuItem("Reminder",
                "Fires exactly on time", TYPE_REMINDER, null));
    }
}

// ── Wake Window picker ───────────────────────────────────────────────────────
class WindowPicker extends FieldPicker {
    function initialize(a as Dictionary, e as AlarmEditView) {
        FieldPicker.initialize("Wake Window", "win", a, e);
        for (var i = 0; i < WINDOW_OPTIONS.size(); i++) {
            var m = WINDOW_OPTIONS[i];
            addItem(new WatchUi.MenuItem(m.format("%d") + " min before",
                    null, m, null));
        }
    }
}

// ── Alert-mode picker ────────────────────────────────────────────────────────
class ModePicker extends FieldPicker {
    function initialize(a as Dictionary, e as AlarmEditView) {
        FieldPicker.initialize("Alert", "mode", a, e);
        addItem(new WatchUi.MenuItem("Sound + Vibrate", null, MODE_BOTH, null));
        addItem(new WatchUi.MenuItem("Sound only",      null, MODE_SOUND, null));
        addItem(new WatchUi.MenuItem("Vibrate only",    null, MODE_VIBE, null));
    }
}

// ── Days picker (multi-select checkboxes) ────────────────────────────────────
class DaysPicker extends WatchUi.CheckboxMenu {

    public var alarm as Dictionary;
    public var edit as AlarmEditView;

    function initialize(a as Dictionary, e as AlarmEditView) {
        CheckboxMenu.initialize({:title => "Days"});
        alarm = a;
        edit = e;
        var names = ["Sunday", "Monday", "Tuesday", "Wednesday",
                     "Thursday", "Friday", "Saturday"];
        var mask = AlarmStore.days(a);
        for (var i = 0; i < 7; i++) {
            var checked = (mask & (1 << i)) != 0;
            addItem(new WatchUi.CheckboxMenuItem(names[i], null, i, checked, null));
        }
    }

    // Recompute the bitmask from the current checkbox states.
    function recompute() as Void {
        var mask = 0;
        for (var i = 0; i < 7; i++) {
            var item = getItem(i) as WatchUi.CheckboxMenuItem;
            if (item.isChecked()) { mask |= (1 << i); }
        }
        alarm.put("days", mask);
        edit.persist();
    }
}

class DaysPickerDelegate extends WatchUi.Menu2InputDelegate {

    private var _picker as DaysPicker;

    function initialize(picker as DaysPicker) {
        Menu2InputDelegate.initialize();
        _picker = picker;
    }

    // Toggling a checkbox fires onSelect; recompute the mask each time.
    function onSelect(item as WatchUi.MenuItem) as Void {
        _picker.recompute();
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
