// AlarmListView.mc
// The home screen. Shows ONE alarm at a time, big and centred, so nothing ever
// overlaps and it stays readable on any screen shape. UP/DOWN move between
// alarms (and the "Add alarm" slot at the end); START/tap opens the highlighted
// one. Reads live from storage, so it's never stale.
//
// Colours: white text on a black background (black saves AMOLED battery too).

import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class AlarmListView extends WatchUi.View {

    private var _sel as Number = 0;
    private var _w as Number = 260;
    private var _h as Number = 260;
    private var _cx as Number = 130;
    private var _cy as Number = 130;

    function initialize() { View.initialize(); }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    function rowCount() as Number { return AlarmStore.getAlarms().size() + 1; }
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
        var n = alarms.size() + 1;
        if (_sel >= n) { _sel = n - 1; }
        if (_sel < 0)  { _sel = 0; }

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Title
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h * 10 / 100, Graphics.FONT_XTINY, "SMART ALARM",
                    Graphics.TEXT_JUSTIFY_CENTER);

        if (_sel >= alarms.size()) {
            // The "Add alarm" slot
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy - 12, Graphics.FONT_MEDIUM, "+ Add alarm",
                        Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            var a = alarms[_sel] as Dictionary;
            var on = AlarmStore.isOn(a);

            // Time (big). FONT_MEDIUM (not FONT_NUMBER_*) so "AM"/"PM" renders.
            dc.setColor(on ? Graphics.COLOR_WHITE : 0x777777, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy - 40, Graphics.FONT_LARGE,
                        Fmt.time12(AlarmStore.hour(a), AlarmStore.minute(a)),
                        Graphics.TEXT_JUSTIFY_CENTER);

            // Label
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy + 8, Graphics.FONT_SMALL, AlarmStore.label(a),
                        Graphics.TEXT_JUSTIFY_CENTER);

            // Days / once
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy + 34, Graphics.FONT_XTINY,
                        Fmt.days(AlarmStore.days(a)), Graphics.TEXT_JUSTIFY_CENTER);

            // On / off badge
            if (!on) {
                dc.setColor(0x999999, Graphics.COLOR_TRANSPARENT);
                dc.drawText(_cx, _cy + 54, Graphics.FONT_XTINY, "OFF",
                            Graphics.TEXT_JUSTIFY_CENTER);
            }
        }

        // Position indicator with up/down arrows
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h - 30, Graphics.FONT_XTINY,
                    (_sel + 1).format("%d") + " / " + n.format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER);
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
    function onSelect() as Boolean { _open(); return true; }
    function onTap(evt as WatchUi.ClickEvent) as Boolean { _open(); return true; }

    private function _open() as Void {
        var alarms = AlarmStore.getAlarms();
        var sel = _view.selected();
        if (sel >= alarms.size()) {
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
