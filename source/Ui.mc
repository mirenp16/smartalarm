// Ui.mc
// Shared button indicators drawn as coloured arcs on the bezel, pointing at the
// physical button that performs the action. Angles use Garmin's drawArc system
// (0 = 3 o'clock, 90 = 12 o'clock, counter-clockwise). Positions matched to the
// Forerunner 265S layout:
//   START/STOP  #5  top-right    (2 o'clock  =  30 deg)
//   BACK        #6  bottom-right (4 o'clock  = 330 deg)
//   UP          #3  mid-left     (9 o'clock  = 180 deg)
//   DOWN        #4  lower-left   (8 o'clock  = 210 deg)
//   LIGHT       #2  top-left     (10 o'clock = 150 deg)  -- reserved by system, unused
//
// Colours can be overridden (e.g. red Snooze, green I'm Awake) via at().

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

    // Draw an arc at `deg` plus a label just inside it.
    static function at(dc as Graphics.Dc, w as Number, h as Number,
                       deg as Number, color as Number, label as String?) as Void {
        var cx = w / 2;
        var cy = h / 2;
        var r = cx - 5;
        dc.setPenWidth(7);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, deg - 13, deg + 13);
        dc.setPenWidth(1);

        if (label != null) {
            var rad = deg.toFloat() * 0.0174533;
            var lr = cx - 52;
            var lx = (cx + lr * Math.cos(rad)).toNumber();
            var ly = (cy - lr * Math.sin(rad)).toNumber();
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            dc.drawText(lx, ly, Graphics.FONT_XTINY, label,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    static function start(dc as Graphics.Dc, w as Number, h as Number, label as String?) as Void {
        at(dc, w, h, UI_DEG_START, UI_GREEN, label);
    }
    static function back(dc as Graphics.Dc, w as Number, h as Number, label as String?) as Void {
        at(dc, w, h, UI_DEG_BACK, UI_RED, label);
    }
    static function up(dc as Graphics.Dc, w as Number, h as Number, label as String?) as Void {
        at(dc, w, h, UI_DEG_UP, UI_BLUE, label);
    }
    static function down(dc as Graphics.Dc, w as Number, h as Number, label as String?) as Void {
        at(dc, w, h, UI_DEG_DOWN, UI_RED, label);
    }
}
