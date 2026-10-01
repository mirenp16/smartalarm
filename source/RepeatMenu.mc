// RepeatMenu.mc
// Chooses how an alarm repeats, using named presets instead of raw day lists:
//
//   Once      fires a single time, then switches itself off
//   Daily     every day
//   4x10      Monday to Thursday
//   Weekdays  Monday to Friday
//   Weekend   Saturday and Sunday
//   Custom    opens the day checkboxes for anything else
//
// Selecting a preset writes its bitmask straight into the working alarm.

import Toybox.Lang;
import Toybox.WatchUi;

class RepeatMenu extends WatchUi.Menu2 {

    public var alarm as Dictionary;

    function initialize(working as Dictionary) {
        Menu2.initialize({:title => "Repeat"});
        alarm = working;

        var current = AlarmStore.days(working);
        addPreset("Once",     DAYS_ONCE,     current);
        addPreset("Daily",    DAYS_ALL,      current);
        addPreset("4x10",     DAYS_4X10,     current);
        addPreset("Weekdays", DAYS_WEEKDAYS, current);
        addPreset("Weekend",  DAYS_WEEKEND,  current);

        // "Custom" is marked selected when the mask matches no preset.
        var isCustom = !(current == DAYS_ONCE || current == DAYS_ALL
                      || current == DAYS_4X10 || current == DAYS_WEEKDAYS
                      || current == DAYS_WEEKEND);
        addItem(new WatchUi.MenuItem("Custom",
            isCustom ? Fmt.days(current) : "Pick days",
            REPEAT_CUSTOM, null));
    }

    private function addPreset(name as String, mask as Number, current as Number) as Void {
        addItem(new WatchUi.MenuItem(name,
            (current == mask) ? "Selected" : null, mask, null));
    }

    // Custom Days edits the working alarm while this menu is covered.
    // Refresh when it returns so the selection summary matches those edits.
    function onShow() as Void {
        var current = AlarmStore.days(alarm);
        var presets = [DAYS_ONCE,DAYS_ALL,DAYS_4X10,DAYS_WEEKDAYS,DAYS_WEEKEND];
        var custom = true;
        for (var i=0;i<presets.size();i++) {
            var selected = current == presets[i];
            if (selected) { custom = false; }
            var item = getItem(i);
            if (item != null) { item.setSubLabel(selected ? "Selected" : null); }
        }
        var customItem = getItem(5);
        if (customItem != null) { customItem.setSubLabel(custom ? Fmt.days(current) : "Pick days"); }
    }
}

class RepeatMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _menu as RepeatMenu;

    function initialize(menu as RepeatMenu) {
        Menu2InputDelegate.initialize();
        _menu = menu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId() as Number;

        if (id == REPEAT_CUSTOM) {
            // Hand off to the day checkboxes.
            var dp = new DaysPicker(_menu.alarm);
            WatchUi.pushView(dp, new DaysPickerDelegate(dp), WatchUi.SLIDE_LEFT);
            return;
        }

        _menu.alarm.put("days", id);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
