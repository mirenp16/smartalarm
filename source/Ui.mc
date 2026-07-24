// Ui.mc
// Shared button indicators drawn as coloured arcs on the bezel, pointing at the
// physical button that performs the action (like Garmin's own confirm screens):
//   START  = top-right   (green)
//   BACK   = bottom-right (red)
//   UP     = mid-left     (blue)
//   DOWN   = lower-left   (blue)
//
// NOTE: the LIGHT button (top-left) is reserved by the system for the backlight
// and does not reliably reach an app, so it is never used for actions here.

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

class Ui {

    // Draw a short arc at `deg` (Garmin angle: 0=right, 90=top, CCW) plus a label
    // just inside it.
    static function arc(dc as Graphics.Dc, w as Number, h as Number,
                        deg as Number, color as Number, label as String?) as Void {
        var cx = w / 2;
        var cy = h / 2;
        var r = cx - 5;
        dc.setPenWidth(6);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, deg - 12, deg + 12);
        dc.setPenWidth(1);

        if (label != null) {
            var rad = deg.toFloat() * 0.0174533;
            var lr = cx - 44;
            var lx = (cx + lr * Math.cos(rad)).toNumber();
            var ly = (cy - lr * Math.sin(rad)).toNumber();
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawText(lx, ly - 12, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    static function start(dc as Graphics.Dc, w as Number, h as Number, label as String?) as Void {
        arc(dc, w, h, 52, 0x00DD44, label);      // green, top-right
    }
    static function back(dc as Graphics.Dc, w as Number, h as Number, label as String?) as Void {
        arc(dc, w, h, 308, 0xFF4444, label);     // red, bottom-right
    }
    static function up(dc as Graphics.Dc, w as Number, h as Number, label as String?) as Void {
        arc(dc, w, h, 150, 0x33AAFF, label);     // blue, mid-left
    }
    static function down(dc as Graphics.Dc, w as Number, h as Number, label as String?) as Void {
        arc(dc, w, h, 210, 0x33AAFF, label);     // blue, lower-left
    }
}
