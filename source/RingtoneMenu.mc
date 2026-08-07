// RingtoneMenu.mc
// Picks the ringtone for an alarm and previews it as you scroll, so you can hear
// what you're choosing. Only reachable when the alarm's Alert makes sound.

import Toybox.Lang;
import Toybox.WatchUi;

class RingtoneMenu extends WatchUi.Menu2 {

    public var alarm as Dictionary;

    function initialize(working as Dictionary) {
        Menu2.initialize({:title => "Ringtone"});
        alarm = working;
        var names = Ringtone.names();
        for (var i = 0; i < names.size(); i++) {
            addItem(new WatchUi.MenuItem(names[i] as String, null, i, null));
        }
    }
}

class RingtoneMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _menu as RingtoneMenu;

    function initialize(menu as RingtoneMenu) {
        Menu2InputDelegate.initialize();
        _menu = menu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var idx = item.getId() as Number;
        _menu.alarm.put("tone", idx);
        Ringtone.play(idx);                    // preview the choice
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
