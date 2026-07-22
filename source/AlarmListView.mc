// AlarmListView.mc
// The home screen: a scrollable list of alarms plus an "Add alarm" row.
// Drawn as a 3-row carousel (previous / selected / next) which keeps everything
// inside the safe central band, so it looks right on round OR square screens.
// It reads the alarm list live from storage on every draw, so it's never stale.

import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class AlarmListView extends WatchUi.View {

    private var _sel as Number = 0;   // highlighted row index
    private var _w as Number = 260;
    private var _h as Number = 260;
    private var _cx as Number = 130;
    private var _cy as Number = 130;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();
        _h = dc.getHeight();
        _cx = _w / 2;
        _cy = _h / 2;
    }

    // Number of selectable rows = alarms + 1 (the Add row).
    function rowCount() as Number {
        return AlarmStore.getAlarms().size() + 1;
    }

    function selected() as Number { return _sel; }

    function moveDown() as Void {
        _sel = (_sel + 1) % rowCount();
        WatchUi.requestUpdate();
    }

    function moveUp() as Void {
        var n = rowCount();
        _sel = (_sel + n - 1) % n;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var alarms = AlarmStore.getAlarms();
        var n = alarms.size() + 1;      // include Add row
        if (_sel >= n) { _sel = n - 1; }
        if (_sel < 0)  { _sel = 0; }

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Title
        dc.setColor(0x00CC66, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, 12, Graphics.FONT_XTINY, "SMART ALARM",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Three-row carousel: previous (dim), selected (bright), next (dim)
        _drawRow(dc, alarms, _sel - 1, _cy - 62, false);
        _drawRow(dc, alarms, _sel,     _cy,      true);
        _drawRow(dc, alarms, _sel + 1, _cy + 62, false);

        // Position hint (e.g. "2 / 4")
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h - 24, Graphics.FONT_XTINY,
                    (_sel + 1).format("%d") + " / " + n.format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Draws one row. index may be out of range (blank) or == alarms.size (Add).
    private function _drawRow(dc as Graphics.Dc, alarms as Array,
                              index as Number, y as Number, focused as Boolean) as Void {
        if (index < 0 || index > alarms.size()) { return; }

        // The "Add alarm" row
        if (index == alarms.size()) {
            var c = focused ? 0x00CC66 : 0x556655;
            dc.setColor(c, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, y, focused ? Graphics.FONT_SMALL : Graphics.FONT_XTINY,
                        "+ Add alarm", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var a = alarms[index] as Dictionary;
        var on = AlarmStore.isOn(a);
        var timeStr = Fmt.time12(AlarmStore.hour(a), AlarmStore.minute(a));

        if (focused) {
            // Time (large). Use a regular font (not FONT_NUMBER_*) because the
            // string contains "AM"/"PM", which number-only fonts can't render.
            dc.setColor(on ? Graphics.COLOR_WHITE : 0x666666, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, y - 20, Graphics.FONT_MEDIUM, timeStr,
                        Graphics.TEXT_JUSTIFY_CENTER);
            // Label + days
            dc.setColor(on ? 0x00CC66 : 0x555555, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, y + 18, Graphics.FONT_XTINY,
                        AlarmStore.label(a) + "  -  " + Fmt.days(AlarmStore.days(a)),
                        Graphics.TEXT_JUSTIFY_CENTER);
            if (!on) {
                dc.setColor(0x884400, Graphics.COLOR_TRANSPARENT);
                dc.drawText(_cx, y + 34, Graphics.FONT_XTINY, "OFF",
                            Graphics.TEXT_JUSTIFY_CENTER);
            }
        } else {
            dc.setColor(on ? 0x888888 : 0x444444, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, y, Graphics.FONT_XTINY,
                        timeStr + "   " + AlarmStore.label(a),
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}

class AlarmListDelegate extends WatchUi.BehaviorDelegate {

    private var _view as AlarmListView;

    function initialize(view as AlarmListView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean { _view.moveDown(); return true; }
    function onPreviousPage() as Boolean { _view.moveUp(); return true; }

    // START button = open the highlighted row
    function onSelect() as Boolean {
        _open();
        return true;
    }

    // Touchscreen tap = same as select
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        _open();
        return true;
    }

    private function _open() as Void {
        var alarms = AlarmStore.getAlarms();
        var sel = _view.selected();
        if (sel >= alarms.size()) {
            // Add row -> create the new alarm in storage now, then edit it.
            var na = AlarmStore.newAlarm();
            AlarmStore.addAlarm(na);
            SmartAlarmApp.syncBackground();
            var idx = AlarmStore.getAlarms().size() - 1;
            var view = new AlarmEditView(idx, na);
            WatchUi.pushView(view, new AlarmEditDelegate(view), WatchUi.SLIDE_LEFT);
        } else {
            var a = alarms[sel] as Dictionary;
            var view = new AlarmEditView(sel, a);
            WatchUi.pushView(view, new AlarmEditDelegate(view), WatchUi.SLIDE_LEFT);
        }
    }
}
