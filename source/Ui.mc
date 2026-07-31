// Ui.mc
// Button indicators drawn on the bezel, pointing at the physical button.
// Forerunner 265S positions (Garmin drawArc angles: 0=3 o'clock, 90=12, CCW):
//   START #5 top-right    30 deg     BACK #6 bottom-right 330 deg
//   UP    #3 mid-left     180 deg    DOWN #4 lower-left   210 deg
//   (LIGHT #2 top-left 150 deg is reserved by the system and unused.)
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
const UI_DEG_DOWN  = 210;
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
    static function down(dc as Graphics.Dc, w as Number, h as Number, l as String?) as Void {
        at(dc, w, h, UI_DEG_DOWN, UI_RED, l);
    }

    // Curved-or-vertical text at a bezel angle.
    static function label(dc as Graphics.Dc, w as Number, h as Number,
                          deg as Number, color as Number, text as String) as Void {
        var cx = w / 2;
        var cy = h / 2;
        var vf = _vectorFont();
        if (vf != null && (dc has :drawRadialText)) {
            try {
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                var dir = (deg > 90 && deg < 270)
                    ? Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE
                    : Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE;
                dc.drawRadialText(cx, cy, vf, text, Graphics.TEXT_JUSTIFY_CENTER,
                                  deg, cx - 24, dir);
                return;
            } catch (e) {
            }
        }
        _vertical(dc, cx, cy, deg, color, text);
    }

    private static function _vectorFont() as Graphics.VectorFont? {
        try {
            if (Graphics has :getVectorFont) {
                return Graphics.getVectorFont({
                    :face => ["RobotoCondensedBold", "RobotoBold", "Roboto"],
                    :size => 20
                });
            }
        } catch (e) {
        }
        return null;
    }

    // Fallback: stack the letters vertically near the button.
    private static function _vertical(dc as Graphics.Dc, cx as Number, cy as Number,
                                      deg as Number, color as Number, text as String) as Void {
        var rad = deg.toFloat() * 0.0174533;
        var r = cx - 30;
        var ax = (cx + r * Math.cos(rad)).toNumber();
        var ay = (cy - r * Math.sin(rad)).toNumber();
        var n = text.length();
        var chH = 16;
        var startY = ay - (n * chH) / 2;
        var vc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < n; i++) {
            dc.drawText(ax, startY + i * chH + chH / 2, Graphics.FONT_XTINY,
                        text.substring(i, i + 1), vc);
        }
    }
}
