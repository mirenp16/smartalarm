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

    // Just the "AM"/"PM" suffix.
    static function ampm(hour as Number) as String {
        return (hour >= 12) ? "PM" : "AM";
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

    static function typeName(type as Number) as String {
        return (type == TYPE_REMINDER) ? "Reminder" : "Sleep";
    }

    static function modeName(mode as Number) as String {
        if (mode == MODE_SOUND) { return "Sound Only"; }
        if (mode == MODE_VIBE)  { return "Vibrate Only"; }
        return "Sound + Vibrate";
    }
}
