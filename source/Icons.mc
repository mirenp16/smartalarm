// Icons.mc
// Small status glyphs drawn with primitives (no bitmaps needed, so they stay
// crisp at any size):
//   speaker  - sound on/off (struck through when off)
//   vibe     - vibration waves on/off (struck through when off)
//   toggle   - the green/grey pill switch used on the alarm rows
//
// These mirror the native Garmin alarm list: speaker + vibration side by side,
// with a slash through whichever one is off.

import Toybox.Graphics;
import Toybox.Lang;

class Icons {

    // Speaker glyph centred at (x, y), roughly `s` pixels tall.
    static function speaker(dc as Graphics.Dc, x as Number, y as Number,
                            s as Number, on as Boolean) as Void {
        var c = on ? Graphics.COLOR_WHITE : 0x777777;
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);

        var bh = s / 2;             // box half-height
        var bw = s / 4;             // box half-width
        // Cone body
        dc.fillRectangle(x - bw - 2, y - bh / 2, bw, bh);
        var pts = [
            [x - 2,      y - bh],
            [x + bw,     y - bh],
            [x + bw,     y + bh],
            [x - 2,      y + bh]
        ];
        dc.fillPolygon(pts);

        if (on) {
            // Two sound waves
            dc.setPenWidth(2);
            dc.drawArc(x + bw, y, s / 3, Graphics.ARC_COUNTER_CLOCKWISE, -50, 50);
            dc.drawArc(x + bw, y, s / 2, Graphics.ARC_COUNTER_CLOCKWISE, -40, 40);
            dc.setPenWidth(1);
        } else {
            strike(dc, x, y, s);
        }
    }

    // Vibration glyph: three vertical wave bars.
    static function vibe(dc as Graphics.Dc, x as Number, y as Number,
                         s as Number, on as Boolean) as Void {
        var c = on ? Graphics.COLOR_WHITE : 0x777777;
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var h = s;
        for (var i = -1; i <= 1; i++) {
            var bx = x + i * (s / 3);
            var bh = (i == 0) ? h : (h * 2 / 3);
            dc.drawLine(bx, y - bh / 2, bx, y + bh / 2);
        }
        dc.setPenWidth(1);
        if (!on) { strike(dc, x, y, s); }
    }

    // Diagonal slash marking a glyph as off.
    static function strike(dc as Graphics.Dc, x as Number, y as Number, s as Number) as Void {
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x - s / 2 - 2, y + s / 2, x + s / 2 + 2, y - s / 2);
        dc.setPenWidth(1);
    }

    // Draws the sound + vibration pair for an alert mode, centred on x.
    static function alertPair(dc as Graphics.Dc, x as Number, y as Number,
                              s as Number, mode as Number) as Void {
        var soundOn = (mode == MODE_BOTH || mode == MODE_SOUND);
        var vibeOn  = (mode == MODE_BOTH || mode == MODE_VIBE);
        speaker(dc, x - s, y, s, soundOn);
        vibe(dc, x + s, y, s, vibeOn);
    }

    // Pill toggle: green with the knob right when on, grey with knob left when off.
    static function toggle(dc as Graphics.Dc, x as Number, y as Number,
                           w as Number, h as Number, on as Boolean) as Void {
        var r = h / 2;
        // Track
        dc.setColor(on ? 0x004411 : 0x333333, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - w / 2, y - h / 2, w, h, r);
        dc.setColor(on ? UI_GREEN : 0x888888, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(x - w / 2, y - h / 2, w, h, r);
        dc.setPenWidth(1);
        // Knob
        var ky = on ? (y - h / 2 + r) : (y + h / 2 - r);
        dc.setColor(on ? UI_GREEN : 0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, ky, r - 3);
    }
}
