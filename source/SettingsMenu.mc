// SettingsMenu.mc
// All settings screens live here:
//   SettingsMenu            — top-level menu (Enable/Disable, Set Time, etc.)
//   SettingsMenuDelegate    — handles item selection in top-level menu
//   TimePickerView          — custom hour+minute picker
//   TimePickerDelegate      — input handling for TimePickerView
//   DaysPickerMenu          — toggle each day on/off
//   DaysPickerDelegate      — handles day toggles
//   ModeMenu                — choose alert mode
//   ModeMenuDelegate        — handles mode selection
//   WindowMenu              — choose smart window duration
//   WindowMenuDelegate      — handles window selection

import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Graphics;

// ═══════════════════════════════════════════════════════════════════════════
// TOP-LEVEL SETTINGS MENU
// ═══════════════════════════════════════════════════════════════════════════

class SettingsMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({:title => "Settings"});

        var enabled = AlarmStorage.isAlarmEnabled();

        // Toggle enable/disable
        addItem(new WatchUi.MenuItem(
            enabled ? "Disable Alarm" : "Enable Alarm",
            enabled ? "Currently ON" : "Currently OFF",
            :toggle,
            null
        ));

        addItem(new WatchUi.MenuItem("Set Time",   null, :setTime,   null));
        addItem(new WatchUi.MenuItem("Set Days",   null, :setDays,   null));
        addItem(new WatchUi.MenuItem("Alert Mode", null, :alertMode, null));
        addItem(new WatchUi.MenuItem("Smart Window", "How early to start monitoring",
                                    :window, null));
    }
}

class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();

        if (id == :toggle) {
            var nowEnabled = AlarmStorage.isAlarmEnabled();
            var newState   = !nowEnabled;
            AlarmStorage.setAlarmEnabled(newState);

            if (newState) {
                SmartAlarmApp.registerBackground();
            } else {
                SmartAlarmApp.unregisterBackground();
            }

            // Rebuild menu to reflect new state
            WatchUi.popView(WatchUi.SLIDE_DOWN);
            WatchUi.pushView(new SettingsMenu(), new SettingsMenuDelegate(),
                             WatchUi.SLIDE_UP);

        } else if (id == :setTime) {
            var tpView = new TimePickerView();
            WatchUi.pushView(tpView, new TimePickerDelegate(tpView),
                             WatchUi.SLIDE_LEFT);

        } else if (id == :setDays) {
            WatchUi.pushView(new DaysPickerMenu(), new DaysPickerDelegate(),
                             WatchUi.SLIDE_LEFT);

        } else if (id == :alertMode) {
            WatchUi.pushView(new ModeMenu(), new ModeMenuDelegate(),
                             WatchUi.SLIDE_LEFT);

        } else if (id == :window) {
            WatchUi.pushView(new WindowMenu(), new WindowMenuDelegate(),
                             WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TIME PICKER VIEW
// Custom drawn view: shows hour and minute, UP/DOWN scroll the focused field,
// SELECT moves between hour/minute/confirm.
// ═══════════════════════════════════════════════════════════════════════════

class TimePickerView extends WatchUi.View {

    // 0 = editing hour, 1 = editing minute, 2 = confirm
    private var _focus  as Number = 0;
    private var _hour   as Number;
    private var _minute as Number;

    function initialize() {
        View.initialize();
        _hour   = AlarmStorage.getAlarmHour();
        _minute = AlarmStorage.getAlarmMinute();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Title
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 18, Graphics.FONT_XTINY, "SET ALARM TIME",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Hour
        var hourColor   = (_focus == 0) ? 0x00CC66 : Graphics.COLOR_WHITE;
        dc.setColor(hourColor, Graphics.COLOR_TRANSPARENT);
        var displayHour = _hour % 12;
        if (displayHour == 0) { displayHour = 12; }
        dc.drawText(cx - 40, cy - 30, Graphics.FONT_NUMBER_HOT,
                    displayHour.format("%2d"), Graphics.TEXT_JUSTIFY_RIGHT);

        // Colon
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 30, Graphics.FONT_NUMBER_HOT, ":",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Minute
        var minColor = (_focus == 1) ? 0x00CC66 : Graphics.COLOR_WHITE;
        dc.setColor(minColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 40, cy - 30, Graphics.FONT_NUMBER_HOT,
                    _minute.format("%02d"), Graphics.TEXT_JUSTIFY_LEFT);

        // AM/PM
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 24, Graphics.FONT_SMALL,
                    (_hour >= 12) ? "PM" : "AM",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Instructions
        var hints = ["▲▼ Hour  SELECT→", "▲▼ Min   SELECT→", "SELECT to save"];
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h - 36, Graphics.FONT_XTINY, hints[_focus],
                    Graphics.TEXT_JUSTIFY_CENTER);

        // Confirm button highlight
        if (_focus == 2) {
            dc.setColor(0x00CC66, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h - 20, Graphics.FONT_XTINY, "[ CONFIRM ]",
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // Called by the delegate
    function scrollUp() as Void {
        if (_focus == 0) {
            _hour = (_hour + 1) % 24;
        } else if (_focus == 1) {
            _minute = (_minute + 1) % 60;
        }
        WatchUi.requestUpdate();
    }

    function scrollDown() as Void {
        if (_focus == 0) {
            _hour = (_hour + 23) % 24;
        } else if (_focus == 1) {
            _minute = (_minute + 59) % 60;
        }
        WatchUi.requestUpdate();
    }

    // Move focus forward; returns true when user confirms (focus was 2)
    function selectNext() as Boolean {
        if (_focus < 2) {
            _focus++;
            WatchUi.requestUpdate();
            return false;
        }
        // Confirm: save and exit
        AlarmStorage.saveAlarmHour(_hour);
        AlarmStorage.saveAlarmMinute(_minute);
        return true;
    }
}

class TimePickerDelegate extends WatchUi.BehaviorDelegate {

    private var _view as TimePickerView;

    // The view is passed in directly so we don't have to rely on getCurrentView()
    // being correct at delegate construction time.
    function initialize(view as TimePickerView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        if (_view.selectNext()) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
        return true;
    }

    function onNextPage() as Boolean {   // DOWN button
        _view.scrollDown();
        return true;
    }

    function onPreviousPage() as Boolean {   // UP button
        _view.scrollUp();
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// DAYS PICKER MENU  (checkbox list)
// ═══════════════════════════════════════════════════════════════════════════

class DaysPickerMenu extends WatchUi.CheckboxMenu {

    private var _dayIds as Array<Symbol> =
        [:sun, :mon, :tue, :wed, :thu, :fri, :sat];
    private var _dayLabels as Array<String> =
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

    function initialize() {
        CheckboxMenu.initialize({:title => "Alarm Days"});

        var days = AlarmStorage.getAlarmDays();
        for (var i = 0; i < 7; i++) {
            var checked = (days & (1 << i)) != 0;
            addItem(new WatchUi.CheckboxMenuItem(
                _dayLabels[i], null, _dayIds[i], checked, null
            ));
        }
    }
}

class DaysPickerDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        // Recompute bitmask from all checkboxes
        var menu = WatchUi.getCurrentView()[0] as DaysPickerMenu;
        var days = 0;
        for (var i = 0; i < 7; i++) {
            var cbItem = menu.getItem(i) as WatchUi.CheckboxMenuItem;
            if (cbItem.isChecked()) {
                days |= (1 << i);
            }
        }
        AlarmStorage.saveAlarmDays(days);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ALERT MODE MENU
// ═══════════════════════════════════════════════════════════════════════════

class ModeMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({:title => "Alert Mode"});
        addItem(new WatchUi.MenuItem("Vibrate + Sound", null, :vibeAndSound, null));
        addItem(new WatchUi.MenuItem("Sound Only",      null, :soundOnly,     null));
        addItem(new WatchUi.MenuItem("Vibrate Only",    null, :vibeOnly,      null));
    }
}

class ModeMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if      (id == :vibeAndSound) { AlarmStorage.saveAlarmMode(MODE_VIBE_AND_SOUND); }
        else if (id == :soundOnly)    { AlarmStorage.saveAlarmMode(MODE_SOUND_ONLY); }
        else if (id == :vibeOnly)     { AlarmStorage.saveAlarmMode(MODE_VIBE_ONLY); }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SMART WINDOW MENU
// ═══════════════════════════════════════════════════════════════════════════

class WindowMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({:title => "Smart Window"});
        addItem(new WatchUi.MenuItem("15 min before", null, :w15, null));
        addItem(new WatchUi.MenuItem("30 min before", null, :w30, null));
        addItem(new WatchUi.MenuItem("45 min before", null, :w45, null));
        addItem(new WatchUi.MenuItem("60 min before", null, :w60, null));
    }
}

class WindowMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if      (id == :w15) { AlarmStorage.saveWindowMinutes(15); }
        else if (id == :w30) { AlarmStorage.saveWindowMinutes(30); }
        else if (id == :w45) { AlarmStorage.saveWindowMinutes(45); }
        else if (id == :w60) { AlarmStorage.saveWindowMinutes(60); }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}