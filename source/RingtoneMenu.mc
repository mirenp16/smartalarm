// RingtoneMenu.mc
// Picks the ringtone for an alarm.
//
// Selecting an entry sets it AND plays it, but deliberately stays on the menu:
// popping the view immediately cancelled the sound before it could be heard,
// which is why previews seemed not to work. The chosen row is marked "Selected"
// and BACK returns to the alarm.
//
// If nothing is audible at all, check the watch itself:
//   Hold UP > System > Sound & Vibe > Alert Tones must be On.
// No app can produce sound while the watch's tones are muted.

import Toybox.Lang;
import Toybox.WatchUi;

class RingtoneMenu extends WatchUi.Menu2 {

    public var alarm as Dictionary;

    function initialize(working as Dictionary) {
        Menu2.initialize({:title => "Ringtone"});
        alarm = working;
        var names = Ringtone.names();
        var current = AlarmStore.ringtone(working);
        for (var i = 0; i < names.size(); i++) {
            addItem(new WatchUi.MenuItem(
                names[i] as String,
                (i == current) ? "Selected" : null,
                i, null));
        }
    }

    // Refresh which row is marked as selected.
    function refresh() as Void {
        var current = AlarmStore.ringtone(alarm);
        var n = Ringtone.count();
        for (var i = 0; i < n; i++) {
            var it = getItem(i);
            if (it != null) {
                it.setSubLabel((i == current) ? "Selected" : null);
            }
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
        _menu.refresh();
        Ringtone.play(idx);        // stays on screen so the tone is audible
        WatchUi.requestUpdate();
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
