// SettingsView.mc
// Global settings: how long each snooze lasts and how many snoozes are allowed
// before only Dismiss works. UP/DOWN move between the two settings; START cycles
// the highlighted value; changes save immediately. BACK/LIGHT returns.

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class SettingsView extends WatchUi.View {

    private var _lenOptions as Array = [1, 3, 5, 10, 15];
    private var _maxOptions as Array = [1, 2, 3, 4, 5, 10];
    private var _sel as Number = 0;   // 0 = snooze length, 1 = max snoozes
    private var _w as Number = 260;
    private var _h as Number = 260;
    private var _cx as Number = 130;
    private var _cy as Number = 130;

    function initialize() { View.initialize(); }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    function moveDown() as Void { _sel = (_sel + 1) % 2; WatchUi.requestUpdate(); }
    function moveUp() as Void { _sel = (_sel + 1) % 2; WatchUi.requestUpdate(); }

    // Cycle the highlighted setting to its next value and save.
    function cycle() as Void {
        if (_sel == 0) {
            var cur = AlarmStore.snoozeMinutes();
            AlarmStore.setSnoozeMinutes(_next(_lenOptions, cur));
        } else {
            var cur = AlarmStore.maxSnooze();
            AlarmStore.setMaxSnooze(_next(_maxOptions, cur));
        }
        WatchUi.requestUpdate();
    }

    private function _next(opts as Array, cur as Number) as Number {
        for (var i = 0; i < opts.size(); i++) {
            if (opts[i] == cur) { return opts[(i + 1) % opts.size()]; }
        }
        return opts[0];
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h * 12 / 100, Graphics.FONT_XTINY, "SETTINGS",
                    Graphics.TEXT_JUSTIFY_CENTER);

        var title = (_sel == 0) ? "Snooze Length" : "Max Snoozes";
        var value = (_sel == 0)
            ? (AlarmStore.snoozeMinutes().format("%d") + " Minutes")
            : AlarmStore.maxSnooze().format("%d");

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 26, Graphics.FONT_MEDIUM, title, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0xCCCCCC, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + 12, Graphics.FONT_SMALL, value, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h * 70 / 100, Graphics.FONT_XTINY,
                    (_sel + 1).format("%d") + " / 2", Graphics.TEXT_JUSTIFY_CENTER);

        Ui.start(dc, _w, _h, "Change");
        Ui.back(dc, _w, _h, "Back");
    }
}

class SettingsDelegate extends WatchUi.BehaviorDelegate {

    private var _view as SettingsView;

    function initialize(view as SettingsView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean { _view.moveDown(); return true; }
    function onPreviousPage() as Boolean { _view.moveUp(); return true; }
    function onSelect() as Boolean { _view.cycle(); return true; }
    function onTap(evt as WatchUi.ClickEvent) as Boolean { _view.cycle(); return true; }

    function onBack() as Boolean { WatchUi.popView(WatchUi.SLIDE_RIGHT); return true; }
}
