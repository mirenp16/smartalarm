// MainListMenu.mc
// The home screen, built with Garmin's native Menu2 so it looks like the built-in
// alarm app (title header + scrollable rows + gold highlight). Rebuilt fresh on
// every entry, so the "X Alarms On" count and each row are always current.
//
//   Title  : "X Alarms On"
//   Row 1  : Active Alarm Mode   (enter this for alarms to actually ring)
//   Rows   : each saved alarm (time / days / On|Off)
//   Last   : Add Alarm  (blocked at 20 saved alarms)

import Toybox.Lang;
import Toybox.WatchUi;

class MainListMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({:title => titleText()});

        addItem(new WatchUi.MenuItem("Active Alarm Mode", "Enter to arm alarms", :active, null));

        var list = AlarmStore.getAlarms();
        for (var i = 0; i < list.size(); i++) {
            var a = list[i] as Dictionary;
            var sub = Fmt.days(AlarmStore.days(a)) + (AlarmStore.isOn(a) ? "   On" : "   Off");
            addItem(new WatchUi.MenuItem(
                Fmt.time12(AlarmStore.hour(a), AlarmStore.minute(a)), sub, i, null));
        }

        var addSub = AlarmStore.isFull() ? "Max 20 reached" : null;
        addItem(new WatchUi.MenuItem("Add Alarm", addSub, :add, null));
    }

    static function titleText() as String {
        var c = AlarmStore.countOn();
        if (c == 0) { return "No Alarms On"; }
        if (c == 1) { return "1 Alarm On"; }
        return c.format("%d") + " Alarms On";
    }

    // Replace whatever is on screen with a fresh main list.
    // (transition is left untyped: it's a WatchUi.SlideType constant.)
    static function show(transition) as Void {
        var m = new MainListMenu();
        WatchUi.switchToView(m, new MainListDelegate(m), transition);
    }
}

class MainListDelegate extends WatchUi.Menu2InputDelegate {

    function initialize(menu as MainListMenu) {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();

        if (id == :active) {
            var bv = new BedsideView();
            WatchUi.switchToView(bv, new BedsideDelegate(bv), WatchUi.SLIDE_UP);

        } else if (id == :add) {
            if (AlarmStore.isFull()) {
                var msg = "Max number of saved alarms reached. Delete saved alarms to add more!";
                WatchUi.pushView(new MessageView(msg), new MessageDelegate(), WatchUi.SLIDE_UP);
            } else {
                var working = AlarmStore.newAlarm();
                var tp = new TimePickerView(working);
                WatchUi.switchToView(tp, new TimePickerDelegate(tp, true, working), WatchUi.SLIDE_LEFT);
            }

        } else {
            // id is the alarm's list index
            var idx = id as Number;
            var a = AlarmStore.getAlarms()[idx] as Dictionary;
            var working = AlarmStore.clone(a);
            working.put("on", true);   // editing re-arms
            var m = new AlarmDetailMenu(idx, working, false);
            WatchUi.switchToView(m, new AlarmDetailDelegate(m), WatchUi.SLIDE_LEFT);
        }
    }
}
