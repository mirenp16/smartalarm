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
    static function alertPair(dc as Graphics.Dc, x as Number, y as Number,
                              mode as Number, large as Boolean) as Void {
        var soundOn = (mode == MODE_BOTH || mode == MODE_SOUND);
        var vibeOn  = (mode == MODE_BOTH || mode == MODE_VIBE);

        var sIcon = large
            ? (soundOn ? bmp("sl", Rez.Drawables.IconSoundL) : bmp("nsl", Rez.Drawables.IconNoSoundL))
            : (soundOn ? bmp("ss", Rez.Drawables.IconSoundS) : bmp("nss", Rez.Drawables.IconNoSoundS));
        var vIcon = large
            ? (vibeOn ? bmp("vl", Rez.Drawables.IconVibeL) : bmp("nvl", Rez.Drawables.IconNoVibeL))
            : (vibeOn ? bmp("vs", Rez.Drawables.IconVibeS) : bmp("nvs", Rez.Drawables.IconNoVibeS));

        var gap = large ? 6 : 3;
        var sw = (sIcon != null) ? sIcon.getWidth() : 0;
        var vw = (vIcon != null) ? vIcon.getWidth() : 0;
        var total = sw + gap + vw;
        var left = x - total / 2;

        if (sIcon != null) {
            dc.drawBitmap(left, y - sIcon.getHeight() / 2, sIcon);
        }
        if (vIcon != null) {
            dc.drawBitmap(left + sw + gap, y - vIcon.getHeight() / 2, vIcon);
        }
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
