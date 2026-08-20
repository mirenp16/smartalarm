// Format.mc
// Small display-formatting helpers shared by the list, editor, and ringing views.
// Foreground-only (no background use), so no (:background) annotation needed.

import Toybox.Lang;

class Fmt {

    // "7:30 AM" style, from 24h hour + minute.
    static function time12(hour as Number, minute as Number) as String {
        var ampm = (hour >= 12) ? "PM" : "AM";
        var h = hour % 12;
        if (h == 0) { h = 12; }
        return h.format("%d") + ":" + minute.format("%02d") + " " + ampm;
    }


    // "HH:MM" remaining, from a number of seconds. "--:--" when there is
    // nothing to count down to.
    //
    // Rounds UP to the next whole minute so the figure agrees with the clock
    // shown beside it: at 1:05:30 with an alarm at 4:07, truncating gives 03:01
    // while the two displayed times plainly read three hours and two minutes.
    static function duration(secs as Number) as String {
        if (secs < 0) { return "--:--"; }
        var mins = (secs + 59) / 60;
        var h = mins / 60;
        var m = mins % 60;
        return h.format("%02d") + ":" + m.format("%02d");
    }

    // Human-readable repeat summary from a bitmask. Named presets first, then a
    // day list for anything custom.
    static function days(mask as Number) as String {
        if (mask == DAYS_ONCE)     { return "Once"; }
        if (mask == DAYS_ALL)      { return "Daily"; }
        if (mask == DAYS_4X10)     { return "4x10"; }
        if (mask == DAYS_WEEKDAYS) { return "Weekdays"; }
        if (mask == DAYS_WEEKEND)  { return "Weekend"; }

        var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        var out = "";
        var shown = 0;
        for (var i = 0; i < 7; i++) {
            if ((mask & (1 << i)) != 0) {
                if (shown == 3) { return out + "..."; }   // cap at three days
                if (out.length() > 0) { out += ", "; }
                out += names[i];
                shown++;
            }
        }
        return out;
    }


    static function modeName(mode as Number) as String {
        if (mode == MODE_SOUND) { return "Sound Only"; }
        if (mode == MODE_VIBE)  { return "Vibrate Only"; }
        return "Sound + Vibrate";
    }
}
