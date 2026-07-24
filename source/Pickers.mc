// Pickers.mc
// The one remaining menu-style picker: choosing which days an alarm repeats.
// (Single-choice pickers now use the readable ChoiceView instead.)
// Leaving all days unchecked makes the alarm one-time ("Once").
// Toggles write straight into the working alarm; the editor saves on close.

import Toybox.Lang;
import Toybox.WatchUi;

class DaysPicker extends WatchUi.CheckboxMenu {

    public var alarm as Dictionary;

    function initialize(a as Dictionary) {
        CheckboxMenu.initialize({:title => "Scheduled Days"});
        alarm = a;
        var names = ["Sunday", "Monday", "Tuesday", "Wednesday",
                     "Thursday", "Friday", "Saturday"];
        var mask = AlarmStore.days(a);
        for (var i = 0; i < 7; i++) {
            var checked = (mask & (1 << i)) != 0;
            addItem(new WatchUi.CheckboxMenuItem(names[i], null, i, checked, null));
        }
    }

    function recompute() as Void {
        var mask = 0;
        for (var i = 0; i < 7; i++) {
            var item = getItem(i) as WatchUi.CheckboxMenuItem;
            if (item.isChecked()) { mask |= (1 << i); }
        }
        alarm.put("days", mask);
    }
}

class DaysPickerDelegate extends WatchUi.Menu2InputDelegate {

    private var _picker as DaysPicker;

    function initialize(picker as DaysPicker) {
        Menu2InputDelegate.initialize();
        _picker = picker;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        _picker.recompute();
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
