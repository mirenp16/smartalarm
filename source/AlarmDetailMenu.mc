// AlarmDetailMenu.mc
// Native-style settings list for one alarm (add or edit). Works on a COPY; only
// "Done"/"Save" writes to storage. Sub-values are picked on their own screens and
// the sublabels refresh when we return (onShow).
//
// Edit order: Status, Time, Repeat, Label, Sleep Cycle Window, Alert,
//             Snooze Length, Max Snoozes, Done, Delete Alarm.
// Add order : Save, Time, Repeat, Label, Sleep Cycle Window, Alert,
//             Snooze Length, Max Snoozes.

import Toybox.Lang;
import Toybox.WatchUi;

class AlarmDetailMenu extends WatchUi.Menu2 {

    public var alarm as Dictionary;
    public var index as Number;
    public var isNew as Boolean;
    // Set when the delete confirmation says yes. We can't switch views from inside
    // onResponse (the dialog pops back on top of us), so we do it on the next show.
    public var pendingClose as Boolean = false;

    function initialize(idx as Number, working as Dictionary, brandNew as Boolean) {
        Menu2.initialize({:title => Fmt.time12(AlarmStore.hour(working), AlarmStore.minute(working))});
        index = idx;
        alarm = working;
        isNew = brandNew;

        if (isNew) {
            addItem(new WatchUi.MenuItem("Save", null, :save, null));
        } else {
            addItem(new WatchUi.ToggleMenuItem("Status", null, :status,
                AlarmStore.isOn(working), null));
        }
        addItem(new WatchUi.MenuItem("Time", timeSub(), :time, null));
        addItem(new WatchUi.MenuItem("Repeat", daysSub(), :days, null));
        addItem(new WatchUi.MenuItem("Label", labelSub(), :label, null));
        addItem(new WatchUi.MenuItem("Sleep Cycle Window", winSub(), :win, null));
        addItem(new WatchUi.MenuItem("Alert", modeSub(), :mode, null));
        addItem(new WatchUi.MenuItem("Ringtone", toneSub(), :tone, null));
        addItem(new WatchUi.MenuItem("Snooze Length", snLenSub(), :snlen, null));
        addItem(new WatchUi.MenuItem("Max Snoozes", snMaxSub(), :snmax, null));
        addItem(new WatchUi.ToggleMenuItem("Passcode", null, :pc,
            AlarmStore.passcodeOn(working), null));
        if (!isNew) {
            addItem(new WatchUi.MenuItem("Done", null, :done, null));
            addItem(new WatchUi.MenuItem("Delete Alarm", null, :delete, null));
        }
    }

    // Refresh sublabels + title when returning from a sub-picker.
    function onShow() as Void {
        if (pendingClose) {
            pendingClose = false;
            MainListMenu.show(WatchUi.SLIDE_RIGHT);
            return;
        }
        setTitle(Fmt.time12(AlarmStore.hour(alarm), AlarmStore.minute(alarm)));
        _set(:time, timeSub());
        _set(:days, daysSub());
        _set(:label, labelSub());
        _set(:win, winSub());
        _set(:mode, modeSub());
        _set(:tone, toneSub());
        _set(:snlen, snLenSub());
        _set(:snmax, snMaxSub());
    }

    // True when the alarm actually makes sound, so Ringtone is meaningful.
    function soundEnabled() as Boolean {
        var m = AlarmStore.mode(alarm);
        return (m == MODE_BOTH || m == MODE_SOUND);
    }

    // findItemById returns the item's INDEX (-1 if absent), not the item itself.
    private function _set(id as Symbol, sub as String) as Void {
        var idx = findItemById(id);
        if (idx != null && idx >= 0) {
            var item = getItem(idx);
            if (item != null) { item.setSubLabel(sub); }
        }
    }

    function timeSub()  as String { return Fmt.time12(AlarmStore.hour(alarm), AlarmStore.minute(alarm)); }
    function daysSub()  as String { return Fmt.days(AlarmStore.days(alarm)); }
    function labelSub() as String { return AlarmStore.label(alarm); }
    function winSub()   as String { return AlarmStore.window(alarm).format("%d") + " Minutes"; }
    // The "watch tones are muted" warning lives on the Alert screen itself
    // (see ChoiceView), where there's room to show it clearly.
    function modeSub()  as String { return Fmt.modeName(AlarmStore.mode(alarm)); }
    // Ringtone only means something when the alarm actually makes sound.
    function toneSub()  as String {
        if (!soundEnabled()) { return "Not Applicable"; }
        return Ringtone.nameAt(AlarmStore.ringtone(alarm));
    }
    function snLenSub() as String { return AlarmStore.snoozeLen(alarm).format("%d") + " Minutes"; }
    function snMaxSub() as String { return AlarmStore.maxSnoozeOf(alarm).format("%d"); }
}

class AlarmDetailDelegate extends WatchUi.Menu2InputDelegate {

    private var _menu as AlarmDetailMenu;

    function initialize(menu as AlarmDetailMenu) {
        Menu2InputDelegate.initialize();
        _menu = menu;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var a = _menu.alarm;

        if (id == :status) {
            a.put("on", (item as WatchUi.ToggleMenuItem).isEnabled());

        } else if (id == :pc) {
            a.put("pc", (item as WatchUi.ToggleMenuItem).isEnabled());

        } else if (id == :tone) {
            // Only reachable when the alarm actually makes sound.
            if (!_menu.soundEnabled()) {
                // "|" marks explicit line breaks so this reads cleanly.
                var msg = "Set Alert to|'Sound Only'|OR|'Sound + Vibrate'|first!";
                WatchUi.pushView(new MessageView(msg), new MessageDelegate(), WatchUi.SLIDE_UP);
            } else {
                var tp = new RingtoneMenu(a);
                WatchUi.pushView(tp, new RingtoneMenuDelegate(tp), WatchUi.SLIDE_LEFT);
            }

        } else if (id == :time) {
            var tp = new TimePickerView(a);
            WatchUi.pushView(tp, new TimePickerDelegate(tp, false, a), WatchUi.SLIDE_LEFT);

        } else if (id == :days) {
            var rp = new RepeatMenu(a);
            WatchUi.pushView(rp, new RepeatMenuDelegate(rp), WatchUi.SLIDE_LEFT);

        } else if (id == :label) {
            var lp = new OptionMenu("Label", "label", _labelOptions(), a);
            WatchUi.pushView(lp, new OptionMenuDelegate(lp), WatchUi.SLIDE_LEFT);

        } else if (id == :win) {
            var wd = "Select how far ahead of your set time the app should look for light sleep to wake you up gently";
            var cv = new ChoiceView("Sleep Cycle Window", "win", _winOptions(wd), AlarmStore.window(a), a);
            WatchUi.pushView(cv, new ChoiceDelegate(cv), WatchUi.SLIDE_LEFT);

        } else if (id == :mode) {
            // Uses ChoiceView so each option can show the speaker / vibration icons.
            var cv2 = new ChoiceView("Alert", "mode", _modeChoices(), AlarmStore.mode(a), a);
            WatchUi.pushView(cv2, new ChoiceDelegate(cv2), WatchUi.SLIDE_LEFT);

        } else if (id == :snlen) {
            var sp = new OptionMenu("Snooze Length", "snLen", _snLenOptions(), a);
            WatchUi.pushView(sp, new OptionMenuDelegate(sp), WatchUi.SLIDE_LEFT);

        } else if (id == :snmax) {
            var xp = new OptionMenu("Max Snoozes", "snMax", _snMaxOptions(), a);
            WatchUi.pushView(xp, new OptionMenuDelegate(xp), WatchUi.SLIDE_LEFT);

        } else if (id == :save || id == :done) {
            _commit();

        } else if (id == :delete) {
            var dialog = new WatchUi.Confirmation("Delete this alarm?");
            WatchUi.pushView(dialog, new DetailDeleteDelegate(_menu), WatchUi.SLIDE_UP);
        }
    }

    // BACK on an EXISTING alarm saves your changes (so flipping Status and
    // backing out just works - no need to scroll down to Done). On a NEW alarm
    // it cancels, since that alarm was never saved in the first place.
    function onBack() as Void {
        if (_menu.isNew) {
            MainListMenu.show(WatchUi.SLIDE_RIGHT);
        } else {
            _commit();
        }
    }

    private function _commit() as Void {
        var a = _menu.alarm;
        if (AlarmStore.days(a) == 0) {
            a.put("fireAt", AlarmStore.nextOccurrence(AlarmStore.hour(a), AlarmStore.minute(a)));
        }
        if (_menu.isNew) {
            AlarmStore.addAlarm(a);
        } else {
            AlarmStore.updateAlarm(_menu.index, a);
        }
        AlarmStore.armForNextOccurrence(a);
        MainListMenu.show(WatchUi.SLIDE_RIGHT);
    }

    private function _labelOptions() as Array {
        var names = ["Wake Up!", "Work", "Gym", "Medication", "Meeting", "Study", "Nap", "Reminder"];
        var out = [];
        for (var i = 0; i < names.size(); i++) { out.add([names[i], names[i]]); }
        return out;
    }
    // Built from WINDOW_OPTIONS so the list and the defaults can't drift apart.
    private function _winOptions(desc as String) as Array {
        var out = [];
        for (var i = 0; i < WINDOW_OPTIONS.size(); i++) {
            var m = WINDOW_OPTIONS[i];
            out.add([m, m.format("%d") + " Minutes", desc]);
        }
        return out;
    }
    // [value, name, description] — ChoiceView draws the alert icons for these.
    private function _modeChoices() as Array {
        return [
            [MODE_BOTH,  "Sound + Vibrate", ""],
            [MODE_SOUND, "Sound Only",      ""],
            [MODE_VIBE,  "Vibrate Only",    ""]
        ];
    }
    private function _snLenOptions() as Array {
        var out = [];
        for (var i = 0; i < SNOOZE_LEN_OPTIONS.size(); i++) {
            var m = SNOOZE_LEN_OPTIONS[i];
            out.add([m, m.format("%d") + " Minutes"]);
        }
        return out;
    }
    private function _snMaxOptions() as Array {
        var out = [];
        for (var i = 0; i < SNOOZE_MAX_OPTIONS.size(); i++) {
            var m = SNOOZE_MAX_OPTIONS[i];
            out.add([m, m.format("%d")]);
        }
        return out;
    }
}

// Confirms deletion. Flags the detail menu to close itself once the dialog has
// popped, so we land back on the main list instead of the detail screen.
class DetailDeleteDelegate extends WatchUi.ConfirmationDelegate {
    private var _menu as AlarmDetailMenu;
    function initialize(menu as AlarmDetailMenu) {
        ConfirmationDelegate.initialize();
        _menu = menu;
    }
    function onResponse(response) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            AlarmStore.deleteAlarm(_menu.index);
            _menu.pendingClose = true;
        }
        return true;
    }
}
