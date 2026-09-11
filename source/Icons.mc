// Icons.mc
// Alert status glyphs (sound / vibration) drawn from bitmap resources, plus the
// ON/OFF pill switch used on the alarm rows.
//
// Two glyph sizes are provided: _s (22px) for list rows and _l (36px) for the
// Alert picker. Bitmaps are cached after first load so scrolling stays smooth.

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class Icons {

    // Cached bitmaps (loaded lazily; null until first use).
    private static var _cache = {};

    private static function bmp(key as String, rez) {
        if (_cache.hasKey(key)) { return _cache.get(key); }
        var b = null;
        try {
            b = WatchUi.loadResource(rez);
        } catch (e) {
        }
        _cache.put(key, b);
        return b;
    }

    // Draws the sound + vibration pair centred on (x, y).
    // large=true uses the 36px glyphs, otherwise the 22px ones.
    //
    // For "off" states we draw the PLAIN glyph and stroke a bold red slash over
    // it ourselves. The artwork's own thin strike was almost invisible at row
    // size; a drawn slash stays crisp and is obvious at a glance.
    static function alertPair(dc as Graphics.Dc, x as Number, y as Number,
                              mode as Number, large as Boolean) as Void {
        var soundOn = (mode == MODE_BOTH || mode == MODE_SOUND);
        var vibeOn  = (mode == MODE_BOTH || mode == MODE_VIBE);

        var sIcon = large ? bmp("sl", Rez.Drawables.IconSoundL) : bmp("ss", Rez.Drawables.IconSoundS);
        var vIcon = large ? bmp("vl", Rez.Drawables.IconVibeL)  : bmp("vs", Rez.Drawables.IconVibeS);

        var gap = large ? 8 : 5;
        var sw = (sIcon != null) ? sIcon.getWidth() : 0;
        var vw = (vIcon != null) ? vIcon.getWidth() : 0;
        var total = sw + gap + vw;
        var left = x - total / 2;

        if (sIcon != null) {
            var sh = sIcon.getHeight();
            dc.drawBitmap(left, y - sh / 2, sIcon);
            if (!soundOn) { slash(dc, left, y - sh / 2, sw, sh, large); }
        }
        if (vIcon != null) {
            var vx = left + sw + gap;
            var vh = vIcon.getHeight();
            dc.drawBitmap(vx, y - vh / 2, vIcon);
            if (!vibeOn) { slash(dc, vx, y - vh / 2, vw, vh, large); }
        }
    }

    // Bold red diagonal across a glyph, with a dark outline so it reads clearly
    // against the white artwork underneath.
    private static function slash(dc as Graphics.Dc, x as Number, y as Number,
                                  w as Number, h as Number, large as Boolean) as Void {
        var pad = 1;
        var x1 = x - pad;
        var y1 = y + h + pad;
        var x2 = x + w + pad;
        var y2 = y - pad;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(large ? 7 : 5);
        dc.drawLine(x1, y1, x2, y2);

        dc.setColor(UI_RED, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(large ? 4 : 3);
        dc.drawLine(x1, y1, x2, y2);
        dc.setPenWidth(1);
    }

    // The ON/OFF pill switch, matching the one on the alarm's Status row:
    // a tall rounded track with the knob at the TOP when on (green) and at the
    // BOTTOM when off (grey).
    static function toggle(dc as Graphics.Dc, x as Number, y as Number,
                           w as Number, h as Number, on as Boolean) as Void {
        var r = w / 2;
        var trackColor  = on ? 0x0A3D1A : 0x2B2B2B;
        var borderColor = on ? UI_GREEN : 0x9A9A9A;
        var knobColor   = on ? UI_GREEN : 0xD0D0D0;

        dc.setColor(trackColor, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - w / 2, y - h / 2, w, h, r);

        dc.setColor(borderColor, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(x - w / 2, y - h / 2, w, h, r);
        dc.setPenWidth(1);

        var knobR = r - 3;
        var ky = on ? (y - h / 2 + r) : (y + h / 2 - r);
        dc.setColor(knobColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, ky, knobR);
    }
}
