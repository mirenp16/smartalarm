// Ui.mc
// Shared on-screen button hints so every screen shows the same colour language:
//   green  = the START button (top-right) does the positive action
//   red    = the LIGHT button (top-left) / BACK does the cancel / dismiss action
// Drawn near the bottom, centred, so nothing clips on a round screen.

import Toybox.Graphics;
import Toybox.Lang;

class Ui {

    // greenAction / redAction may be null to hide that hint.
    static function hints(dc as Graphics.Dc, w as Number, h as Number,
                          greenAction as String?, redAction as String?) as Void {
        if (greenAction != null) {
            dc.setColor(0x00DD44, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 80 / 100, Graphics.FONT_XTINY,
                        "START: " + greenAction, Graphics.TEXT_JUSTIFY_CENTER);
        }
        if (redAction != null) {
            dc.setColor(0xFF4444, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h * 88 / 100, Graphics.FONT_XTINY,
                        "LIGHT: " + redAction, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
