// MessageView.mc
// A simple full-screen message popup (e.g. the "max alarms reached" notice).
// Text is word-wrapped to fit the round screen; BACK closes it.

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class MessageView extends WatchUi.View {

    private var _msg as String;
    private var _w as Number = 260;
    private var _h as Number = 260;
    private var _cx as Number = 130;
    private var _cy as Number = 130;

    function initialize(msg as String) {
        View.initialize();
        _msg = msg;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var vc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Long diagnostic text needs a smaller font so nothing is cut off on a
        // round screen; short messages stay large and readable.
        var probe = ChoiceView.wrap(dc, _msg, Graphics.FONT_SMALL, _w * 74 / 100);
        var font = (probe.size() > 4) ? Graphics.FONT_XTINY : Graphics.FONT_SMALL;
        var lh   = (probe.size() > 4) ? 19 : 26;
        var lines = (font == Graphics.FONT_SMALL)
            ? probe
            : ChoiceView.wrap(dc, _msg, Graphics.FONT_XTINY, _w * 80 / 100);

        var n = lines.size();
        if (n > 9) { n = 9; }                     // never overflow the screen
        var y = _cy - ((n - 1) * lh) / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < n; i++) {
            dc.drawText(_cx, y + i * lh, font, lines[i], vc);
        }

        Ui.back(dc, _w, _h, "OK");
    }
}

class MessageDelegate extends WatchUi.BehaviorDelegate {
    function initialize() { BehaviorDelegate.initialize(); }
    function onBack() as Boolean { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
    function onSelect() as Boolean { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
    function onTap(evt as WatchUi.ClickEvent) as Boolean { WatchUi.popView(WatchUi.SLIDE_DOWN); return true; }
}
