// OptionMenu.mc
// A simple native single-choice picker (used for Label, Alert, Snooze Length,
// Max Snoozes). Each option is [value, label]; selecting writes the value into
// the working alarm and returns. The detail screen refreshes its sublabel on show.

import Toybox.Lang;
import Toybox.WatchUi;

class OptionMenu extends WatchUi.Menu2 {

    public var key as String;
    public var alarm as Dictionary;

    function initialize(title as String, fieldKey as String, options as Array, working as Dictionary) {
        Menu2.initialize({:title => title});
        key = fieldKey;
        alarm = working;
        for (var i = 0; i < options.size(); i++) {
            var opt = options[i] as Array;
            addItem(new WatchUi.MenuItem(opt[1] as String, null, opt[0], null));
        }
    }
}

class OptionMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _menu as OptionMenu;

    function initialize(menu as OptionMenu) {
        Menu2InputDelegate.initialize();
        _menu = menu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        _menu.alarm.put(_menu.key, item.getId());
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
