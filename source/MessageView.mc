// MessageView.mc
// A simple full-screen message popup (e.g. the "max alarms reached" notice).
// Text is word-wrapped to fit the round screen; BACK closes it.

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class MessageView extends WatchUi.View {

    private var _msg as String;
    private var _w as Number = 360;
    private var _h as Number = 360;
    private var _cx as Number = 180;
    private var _cy as Number = 180;

    function initialize(msg as String) {
        View.initialize();
        _msg = msg;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        // Read the real screen size straight from the drawing context. Relying on
        // onLayout meant that if it hadn't run yet the view still held its 260x260
        // defaults, so text was centred on x=130 instead of 180 on this 360px
        // screen - it looked shifted left and high rather than centred.
        _w = dc.getWidth();
        _h = dc.getHeight();
        _cx = _w / 2;
        _cy = _h / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var vc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // A message containing "|" is split on those marks, so the caller can
        // control exactly where each line breaks. Otherwise it word-wraps.
        var lines;
        var font;
        var lh;
        if (_msg.find("|") != null) {
            lines = splitLines(_msg);
            font = (lines.size() > 4) ? Graphics.FONT_XTINY : Graphics.FONT_SMALL;
            lh   = (lines.size() > 4) ? 24 : 28;
        } else {
            var probe = ChoiceView.wrap(dc, _msg, Graphics.FONT_SMALL, _w * 74 / 100);
            font = (probe.size() > 4) ? Graphics.FONT_XTINY : Graphics.FONT_SMALL;
            lh   = (probe.size() > 4) ? 19 : 26;
            lines = (font == Graphics.FONT_SMALL)
                ? probe
                : ChoiceView.wrap(dc, _msg, Graphics.FONT_XTINY, _w * 80 / 100);
        }

        var n = lines.size();
        if (n > 9) { n = 9; }                     // never overflow the screen
        var y = _cy - ((n - 1) * lh) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < n; i++) {
            dc.drawText(_cx, y + i * lh, font, lines[i], vc);
        }

        Ui.back(dc, _w, _h, "OK");
    }

    // Splits a message on "|" into explicit lines.
    static function splitLines(s as String) as Array {
        var out = [];
        var start = 0;
        for (var i = 0; i < s.length(); i++) {
            if (s.substring(i, i + 1).equals("|")) {
                out.add(s.substring(start, i));
                start = i + 1;
            }
        }
        out.add(s.substring(start, s.length()));
        return out;
    }
}

class MessageDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    function onBack() as Boolean { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
    function onSelect() as Boolean { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
    function onTap(evt as WatchUi.ClickEvent) as Boolean { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
}
