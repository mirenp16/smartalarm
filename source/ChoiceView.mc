// ChoiceView.mc
// A reusable "pick one option" screen that shows ONE option at a time: its name
// big and centred, with a full (word-wrapped) description underneath. This fixes
// the truncated descriptions from the old menu-style pickers.
//
// UP/DOWN cycle options; START selects (writes into the alarm); LIGHT/BACK cancels.
// The choice is written into the working alarm Dictionary but NOT saved to storage
// here — the editor commits everything when you choose "Save and Close".

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class ChoiceView extends WatchUi.View {

    private var _title as String;
    private var _key as String;
    private var _options as Array;      // [[value, name, desc], ...]
    private var _alarm as Dictionary;
    private var _idx as Number = 0;
    private var _w as Number = 360;
    private var _h as Number = 360;
    private var _cx as Number = 180;
    private var _cy as Number = 180;

    function initialize(title as String, key as String, options as Array,
                        currentValue, alarm as Dictionary) {
        View.initialize();
        _title = title;
        _key = key;
        _options = options;
        _alarm = alarm;
        // Start on the currently-selected option.
        for (var i = 0; i < options.size(); i++) {
            var opt = options[i] as Array;
            if (opt[0].toString().equals(currentValue.toString())) { _idx = i; }
        }
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    function move(delta as Number) as Void {
        var n = _options.size();
        if (n <= 0) { return; }   // modulo by zero would take the app down
        _idx = (_idx + n + delta) % n;
        WatchUi.requestUpdate();
    }

    // Commit the highlighted option into the working alarm.
    function apply() as Void {
        if (_options.size() == 0) { return; }
        var opt = _options[_idx] as Array;
        _alarm.put(_key, opt[0]);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        // move() already refuses to divide by an empty list; drawing has to
        // refuse to INDEX one for the same reason. Every caller builds its
        // options from a non-empty constant today, so this is a guard against a
        // future one, not a live fault - but an out-of-range read here would
        // take the whole app down rather than show a blank screen.
        if (_options.size() == 0) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();
            return;
        }
        if (_idx < 0 || _idx >= _options.size()) { _idx = 0; }
        var opt = _options[_idx] as Array;
        var name = opt[1] as String;
        var desc = opt[2] as String;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Title
        var vc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h * 12 / 100, Graphics.FONT_XTINY, _title, vc);

        var hasDesc = (desc.length() > 0);
        var isAlert = _key.equals("mode");
        var optVal = isAlert ? (opt[0] as Number) : -1;

        // If the watch has its Alert Tones muted, say so above any option that
        // relies on sound. Vibrate Only is unaffected, so it gets no warning.
        var warnTones = isAlert && Ringtone.tonesSuppressed()
                        && (optVal == MODE_SOUND || optVal == MODE_BOTH);
        if (warnTones) {
            dc.setColor(UI_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_cx, _cy - 52, Graphics.FONT_XTINY, "Alert Tones: OFF", vc);
        }

        // Wrap the description first, so the layout can adapt to its height.
        // A fixed 4-line cap silently swallowed the last words if the font
        // measured even slightly wider than expected; the block now tightens and
        // shifts up instead of truncating.
        var lines = null;
        var lineH = 22;
        var descTop = _cy - 8;
        if (hasDesc) {
            lines = ChoiceView.wrap(dc, desc, Graphics.FONT_XTINY, _w * 76 / 100);
            if (lines.size() > 4) {
                lineH = 18;
                descTop = _cy - 30;
            }
        }

        // Option name (big). Sits higher when the description needs the room.
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var nameY = _cy;
        if (hasDesc) {
            nameY = (lines.size() > 4) ? (_cy - 58) : (_cy - 44);
        } else if (isAlert) {
            nameY = _cy - 18;
        }
        dc.drawText(_cx, nameY, Graphics.FONT_MEDIUM, name, vc);

        // Alert options also show the speaker / vibration glyphs.
        if (isAlert) {
            Icons.alertPair(dc, _cx, _cy + 30, optVal, true);
        }

        // Wrapped description
        if (hasDesc) {
            dc.setColor(0xBBBBBB, Graphics.COLOR_TRANSPARENT);
            var y = descTop;
            for (var i = 0; i < lines.size() && i < 6; i++) {
                dc.drawText(_cx, y, Graphics.FONT_XTINY, lines[i], vc);
                y += lineH;
            }
        }

        // Position (e.g. 1 / 4)
        dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h * 72 / 100, Graphics.FONT_XTINY,
                    (_idx + 1).format("%d") + " / " + _options.size().format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER);

        Ui.start(dc, _w, _h, "Select");
        Ui.back(dc, _w, _h, "Cancel");
    }

    // Simple greedy word-wrap using pixel measurement.
    static function wrap(dc as Graphics.Dc, text as String, font, maxW as Number) as Array {
        var lines = [];
        var current = "";
        var start = 0;
        var n = text.length();
        for (var i = 0; i <= n; i++) {
            var isBreak = (i == n) || text.substring(i, i + 1).equals(" ");
            if (isBreak) {
                var word = text.substring(start, i);
                start = i + 1;
                if (word.length() > 0) {
                    var trial = (current.length() == 0) ? word : (current + " " + word);
                    if (dc.getTextWidthInPixels(trial, font) <= maxW) {
                        current = trial;
                    } else {
                        if (current.length() > 0) { lines.add(current); }
                        current = word;
                    }
                }
            }
        }
        if (current.length() > 0) { lines.add(current); }
        return lines;
    }
}

class ChoiceDelegate extends WatchUi.BehaviorDelegate {

    private var _view as ChoiceView;

    function initialize(view as ChoiceView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean { _view.move(1); return true; }
    function onPreviousPage() as Boolean { _view.move(-1); return true; }

    function onSelect() as Boolean {
        _view.apply();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        _view.apply();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
