// AlarmListView.mc
// Home / management screen. One item at a time (an alarm, "+ Add alarm",
// "Alarm Activation Mode", or "Settings"). Reads live from storage.
//
// Controls on an alarm:
//   UP / DOWN  : move between items
//   START      : edit the alarm
//   Hold UP    : toggle ON / OFF (enabling enters Active Alarm mode)
//   Hold DOWN  : delete the alarm (with confirmation)
//   BACK       : leave the app
// (Holds use onKeyPressed/onKeyReleased; short presses fall back to behaviours so
//  navigation always works even if a device doesn't report key hold events.)

import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
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

    function slotCount() as Number { return AlarmStore.getAlarms().size() + 3; }
    function selected() as Number { return _sel; }
    function isAddSlot() as Boolean { return _sel == AlarmStore.getAlarms().size(); }
    function isActivateSlot() as Boolean { return _sel == AlarmStore.getAlarms().size() + 1; }
    function isSettingsSlot() as Boolean { return _sel == AlarmStore.getAlarms().size() + 2; }
    function isAlarmSlot() as Boolean { return _sel < AlarmStore.getAlarms().size(); }

    function moveDown() as Void { _sel = (_sel + 1) % slotCount(); WatchUi.requestUpdate(); }
    function moveUp() as Void {
        var n = slotCount();
        _sel = (_sel + n - 1) % n;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var alarms = AlarmStore.getAlarms();
        var n = alarms.size() + 3;
        if (_sel >= n) { _sel = n - 1; }
        if (_sel < 0)  { _sel = 0; }
        var vc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h * 9 / 100, Graphics.FONT_XTINY, "SMART ALARM", vc);

        if (_sel == alarms.size()) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy, Graphics.FONT_MEDIUM, "+ Add alarm", vc);
            Ui.start(dc, _w, _h, "Open");
        } else if (_sel == alarms.size() + 1) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy - 12, Graphics.FONT_SMALL, "Alarm Activation", vc);
            dc.drawText(_cx, _cy + 12, Graphics.FONT_SMALL, "Mode", vc);
            Ui.start(dc, _w, _h, "Open");
        } else if (_sel == alarms.size() + 2) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy, Graphics.FONT_MEDIUM, "Settings", vc);
            Ui.start(dc, _w, _h, "Open");
        } else {
            var a = alarms[_sel] as Dictionary;
            var on = AlarmStore.isOn(a);

            dc.setColor(on ? Graphics.COLOR_WHITE : 0x777777, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy - 40, Graphics.FONT_LARGE,
                        Fmt.time12(AlarmStore.hour(a), AlarmStore.minute(a)), vc);

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy + 2, Graphics.FONT_SMALL, AlarmStore.label(a), vc);

            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy + 26, Graphics.FONT_XTINY, Fmt.days(AlarmStore.days(a)), vc);

            dc.setColor(on ? UI_GREEN : 0x888888, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy + 46, Graphics.FONT_XTINY, on ? "ENABLED" : "DISABLED", vc);

            // Button arrows: Edit (START), ON/OFF (hold UP), Delete (hold DOWN)
            Ui.start(dc, _w, _h, "Edit");
            Ui.up(dc, _w, _h, "ON / OFF");
            Ui.down(dc, _w, _h, "Delete");
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _h * 72 / 100, Graphics.FONT_XTINY, "Hold UP / DOWN", vc);
        }
    }

    // Toggle enabled state of the highlighted alarm. Returns true if now ON.
    function toggleHighlighted() as Boolean {
        var alarms = AlarmStore.getAlarms();
        if (_sel >= alarms.size()) { return false; }
        var a = alarms[_sel] as Dictionary;
        var nowOn = !AlarmStore.isOn(a);
        a.put("on", nowOn);
        if (nowOn) {
            AlarmStore.clearFired(AlarmStore.id(a));
            if (AlarmStore.days(a) == 0) {
                a.put("fireAt", AlarmStore.nextOccurrence(AlarmStore.hour(a), AlarmStore.minute(a)));
            }
        }
        AlarmStore.updateAlarm(_sel, a);
        SmartAlarmApp.syncBackground();
        WatchUi.requestUpdate();
        return nowOn;
    }

    function highlightedIndex() as Number { return _sel; }
}

class AlarmListDelegate extends WatchUi.BehaviorDelegate {

    private var _view as AlarmListView;
    private var _pressKey as Number = -1;
    private var _pressMs as Number = 0;

    function initialize(view as AlarmListView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // ── Primary: raw key handling so we can detect holds ──────────────────────
    function onKeyPressed(evt as WatchUi.KeyEvent) as Boolean {
        var k = evt.getKey();
        if (k == WatchUi.KEY_ESC) { return false; }   // let BACK exit the app
        _pressKey = k;
        _pressMs = System.getTimer();
        return true;
    }

    function onKeyReleased(evt as WatchUi.KeyEvent) as Boolean {
        var k = evt.getKey();
        if (k == WatchUi.KEY_ESC) { return false; }
        if (k != _pressKey) { return true; }
        var dur = System.getTimer() - _pressMs;
        var held = (dur >= 550);
        if (k == WatchUi.KEY_UP) {
            if (held) { _toggle(); } else { _view.moveUp(); }
        } else if (k == WatchUi.KEY_DOWN) {
            if (held) { _delete(); } else { _view.moveDown(); }
        } else if (k == WatchUi.KEY_ENTER) {
            _open();
        }
        return true;
    }

    // ── Fallback behaviours (used if a device doesn't report key events) ──────
    // (No onMenu here: it could double-fire with the hold-UP toggle and cancel it
    //  out. Enable/disable also lives in the editor's State field as a fallback.)
    function onNextPage() as Boolean { _view.moveDown(); return true; }
    function onPreviousPage() as Boolean { _view.moveUp(); return true; }
    function onSelect() as Boolean { _open(); return true; }

    // ── Helpers ───────────────────────────────────────────────────────────────
    private function _toggle() as Void {
        if (_view.isAlarmSlot()) {
            if (_view.toggleHighlighted()) { _enterActive(); }
        }
    }

    private function _delete() as Void {
        if (_view.isAlarmSlot()) {
            var dialog = new WatchUi.Confirmation("Delete this alarm?");
            WatchUi.pushView(dialog, new ListDeleteConfirmDelegate(_view.highlightedIndex()),
                             WatchUi.SLIDE_UP);
        }
    }

    private function _open() as Void {
        if (_view.isAddSlot()) {
            var na = AlarmStore.newAlarm();
            var v = new AlarmEditView(-1, na, true);
            WatchUi.pushView(v, new AlarmEditDelegate(v), WatchUi.SLIDE_LEFT);
        } else if (_view.isActivateSlot()) {
            _enterActive();
        } else if (_view.isSettingsSlot()) {
            var s = new SettingsView();
            WatchUi.pushView(s, new SettingsDelegate(s), WatchUi.SLIDE_LEFT);
        } else {
            var sel = _view.selected();
            var a = AlarmStore.getAlarms()[sel] as Dictionary;
            // Editing re-arms: default the working copy to enabled.
            var c = AlarmStore.clone(a);
            c.put("on", true);
            var v = new AlarmEditView(sel, c, false);
            WatchUi.pushView(v, new AlarmEditDelegate(v), WatchUi.SLIDE_LEFT);
        }
    }

    private function _enterActive() as Void {
        var bv = new BedsideView();
        WatchUi.switchToView(bv, new BedsideDelegate(bv), WatchUi.SLIDE_UP);
    }
}

// Confirms deleting an alarm from the list (no editor to close).
class ListDeleteConfirmDelegate extends WatchUi.ConfirmationDelegate {
    private var _index as Number;
    function initialize(index as Number) {
        ConfirmationDelegate.initialize();
        _index = index;
    }
    function onResponse(response) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            AlarmStore.deleteAlarm(_index);
            SmartAlarmApp.syncBackground();
            WatchUi.requestUpdate();
        }
        return true;
    }
}
