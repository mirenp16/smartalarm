// Ui.mc
// Button indicators drawn on the bezel, pointing at the physical button.
// Forerunner 265S positions (Garmin drawArc angles: 0=3 o'clock, 90=12, CCW):
//   START #5 top-right     30 deg
//   BACK  #6 bottom-right 330 deg
//   UP    #3 mid-left     180 deg
// DOWN (#4, 210 deg) and LIGHT (#2, 150 deg) are never labelled: DOWN only ever
// scrolls, and LIGHT is reserved by the system for the backlight.
//
// Labels are drawn CURVED along the bezel using a vector font + drawRadialText.
// Those aren't supported on every device, so we fall back to vertical stacked
// letters (which still read nicely around the edge) whenever curved text isn't
// available — the app can never crash on this.

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

const UI_DEG_START = 30;
const UI_DEG_BACK  = 330;
const UI_DEG_UP    = 180;
const UI_GREEN = 0x00DD44;
const UI_RED   = 0xFF4444;
const UI_BLUE  = 0x33AAFF;

class Ui {

    // Arc + curved label at a button position.
    static function at(dc as Graphics.Dc, w as Number, h as Number,
                       deg as Number, color as Number, lbl as String?) as Void {
        var cx = w / 2;
        var cy = h / 2;
        dc.setPenWidth(7);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, cx - 5, Graphics.ARC_COUNTER_CLOCKWISE, deg - 13, deg + 13);
        dc.setPenWidth(1);
        if (lbl != null) { Ui.label(dc, w, h, deg, color, lbl); }
    }

    static function start(dc as Graphics.Dc, w as Number, h as Number, l as String?) as Void {
        at(dc, w, h, UI_DEG_START, UI_GREEN, l);
    }
    static function back(dc as Graphics.Dc, w as Number, h as Number, l as String?) as Void {
        at(dc, w, h, UI_DEG_BACK, UI_RED, l);
    }
    static function up(dc as Graphics.Dc, w as Number, h as Number, l as String?) as Void {
        at(dc, w, h, UI_DEG_UP, UI_BLUE, l);
    }

    // Curved-or-vertical text at a bezel angle. `size` sets the vector font size.
    static function label(dc as Graphics.Dc, w as Number, h as Number,
                          deg as Number, color as Number, text as String) as Void {
        labelSized(dc, w, h, deg, color, text, 20);
    }

    static function labelSized(dc as Graphics.Dc, w as Number, h as Number,
                               deg as Number, color as Number, text as String,
                               size as Number) as Void {
        var cx = w / 2;
        var cy = h / 2;
        var vf = _vectorFont(size);
        if (vf != null && (dc has :drawRadialText)) {
            try {
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                // Upper half of the bezel (deg < 180) arcs UP; the lower half
                // (deg >= 180, plus the UP button at 180) arcs DOWN, so every
                // label reads right-side up.
                var dir = (deg < 180)
                    ? Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE
                    : Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE;
                dc.drawRadialText(cx, cy, vf, text, Graphics.TEXT_JUSTIFY_CENTER,
                                  deg, cx - 24, dir);
                return;
            } catch (e) {
            }
        }
        _vertical(dc, cx, cy, deg, color, text, size);
    }

    // Vector fonts are CACHED per size. Creating one on every draw was the main
    // cause of the overnight "IQ!" crash: Active Alarm Mode redraws every 15 s,
    // so a whole night allocated ~1900 font objects and eventually ran the app
    // out of memory.
    private static var _fontCache = {};

    private static function _vectorFont(size as Number) as Graphics.VectorFont? {
        if (_fontCache.hasKey(size)) { return _fontCache.get(size); }
        var f = null;
        try {
            if (Graphics has :getVectorFont) {
                f = Graphics.getVectorFont({
                    :face => ["RobotoCondensedBold", "RobotoBold", "Roboto"],
                    :size => size
                });
            }
        } catch (e) {
            f = null;
        }
        _fontCache.put(size, f);
        return f;
    }

    // Fallback when curved text isn't available.
    // Short labels stack vertically beside the button; longer ones (like a screen
    // title) are drawn as ordinary horizontal text so they stay readable.
    private static function _vertical(dc as Graphics.Dc, cx as Number, cy as Number,
                                      deg as Number, color as Number, text as String,
                                      size as Number) as Void {
        var vc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);

        if (text.length() > 6) {
            var font = (size >= 26) ? Graphics.FONT_SMALL : Graphics.FONT_XTINY;
            var rad = deg.toFloat() * 0.0174533;
            var ty = (cy - (cx - 26) * Math.sin(rad)).toNumber();
            dc.drawText(cx, ty, font, text, vc);
            return;
        }

        var rad2 = deg.toFloat() * 0.0174533;
        var r = cx - 30;
        var ax = (cx + r * Math.cos(rad2)).toNumber();
        var ay = (cy - r * Math.sin(rad2)).toNumber();
        var n = text.length();
        var chH = 16;
        var startY = ay - (n * chH) / 2;
        for (var i = 0; i < n; i++) {
            dc.drawText(ax, startY + i * chH + chH / 2, Graphics.FONT_XTINY,
                        text.substring(i, i + 1), vc);
        }
    }
}
