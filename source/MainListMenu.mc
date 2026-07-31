// MainListMenu.mc
// The home screen, built with WatchUi.CustomMenu so each alarm row can draw the
// native-looking extras: the green/grey ON-OFF pill and the sound / vibration
// glyphs. Rebuilt fresh on every entry so the "X Alarms On" header and every row
// are always current.
//
//   Title  : alarm logo + "X Alarms On"
//   Row 1  : Active Alarm Mode   (alarms only ring inside this)
//   Rows   : each saved alarm  (time / days / icons / toggle)
//   Last   : Add Alarm  (blocked at 20 saved alarms)

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

const ROW_H = 62;

class MainListMenu extends WatchUi.CustomMenu {

    function initialize() {
        CustomMenu.initialize(ROW_H, Graphics.COLOR_BLACK, {
            :title => new MainListTitle()
        });

        addItem(new SimpleRow(:active, "Active Alarm Mode"));

        var list = AlarmStore.getAlarms();
        for (var i = 0; i < list.size(); i++) {
            addItem(new AlarmRow(i, list[i] as Dictionary));
        }

        addItem(new SimpleRow(:add, "Add Alarm"));
    }

    static function titleText() as String {
        var c = AlarmStore.countOn();
        if (c == 0) { return "No Alarms On"; }
        if (c == 1) { return "1 Alarm On"; }
        return c.format("%d") + " Alarms On";
    }

    // Replace whatever is on screen with a fresh main list.
    static function show(transition) as Void {
        var m = new MainListMenu();
        WatchUi.switchToView(m, new MainListDelegate(), transition);
    }
}

// Header: the app logo with the "X Alarms On" count beneath it.
class MainListTitle extends WatchUi.Drawable {

    function initialize() {
        Drawable.initialize({});
    }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var vc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var logo = null;
        try {
            logo = WatchUi.loadResource(Rez.Drawables.AlarmLogo);
        } catch (e) {
        }
        if (logo != null) {
            dc.drawBitmap(w / 2 - logo.getWidth() / 2, h / 2 - logo.getHeight() - 2, logo);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h - 14, Graphics.FONT_XTINY, MainListMenu.titleText(), vc);
        } else {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL, MainListMenu.titleText(), vc);
        }
    }
}

// A plain text row (Active Alarm Mode / Add Alarm).
class SimpleRow extends WatchUi.CustomMenuItem {

    private var _text as String;

    function initialize(id, text as String) {
        CustomMenuItem.initialize(id, {});
        _text = text;
    }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var vc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var focused = isFocused();

        // "Add Alarm" greys out when the list is full.
        var disabled = (getId() == :add) && AlarmStore.isFull();
        var color = disabled ? 0x666666 : (focused ? Graphics.COLOR_WHITE : 0xBBBBBB);

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2, focused ? Graphics.FONT_SMALL : Graphics.FONT_XTINY, _text, vc);
    }
}

// An alarm row: time, days, sound/vibe glyphs and the ON/OFF pill.
class AlarmRow extends WatchUi.CustomMenuItem {

    private var _index as Number;

    function initialize(index as Number, alarm as Dictionary) {
        CustomMenuItem.initialize(index, {});
        _index = index;
    }

    function draw(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var focused = isFocused();

        var list = AlarmStore.getAlarms();
        if (_index >= list.size()) { return; }
        var a = list[_index] as Dictionary;
        var on = AlarmStore.isOn(a);

        var left = w * 10 / 100;
        var toggleX = w - 26;

        // Time
        dc.setColor(focused ? Graphics.COLOR_WHITE : 0xBBBBBB, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, h / 2 - 14, focused ? Graphics.FONT_SMALL : Graphics.FONT_XTINY,
                    Fmt.time12(AlarmStore.hour(a), AlarmStore.minute(a)),
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Days
        dc.setColor(focused ? 0xCCCCCC : 0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, h / 2 + 12, Graphics.FONT_XTINY, Fmt.days(AlarmStore.days(a)),
                    Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Sound / vibration glyphs
        Icons.alertPair(dc, toggleX - 46, h / 2 + 10, 12, AlarmStore.mode(a));

        // ON/OFF pill
        Icons.toggle(dc, toggleX, h / 2, 18, 36, on);
    }
}

class MainListDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
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
            var idx = id as Number;
            var list = AlarmStore.getAlarms();
            if (idx < 0 || idx >= list.size()) { return; }
            var working = AlarmStore.clone(list[idx] as Dictionary);
            working.put("on", true);   // editing re-arms
            var m = new AlarmDetailMenu(idx, working, false);
            WatchUi.switchToView(m, new AlarmDetailDelegate(m), WatchUi.SLIDE_LEFT);
        }
    }
}
