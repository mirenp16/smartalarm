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

    // Human-readable day summary from a bitmask.
    static function days(mask as Number) as String {
        if (mask == DAYS_ALL)      { return "Every day"; }
        if (mask == DAYS_WEEKDAYS) { return "Mon-Fri"; }
        if (mask == (DAY_SAT | DAY_SUN)) { return "Weekends"; }
        if (mask == 0)             { return "No days set"; }

        var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        var out = "";
        for (var i = 0; i < 7; i++) {
            if ((mask & (1 << i)) != 0) {
                if (out.length() > 0) { out += " "; }
                out += names[i];
            }
        }
        return out;
    }

    static function typeName(type as Number) as String {
        return (type == TYPE_REMINDER) ? "Reminder" : "Sleep";
    }

    static function modeName(mode as Number) as String {
        if (mode == MODE_SOUND) { return "Sound only"; }
        if (mode == MODE_VIBE)  { return "Vibrate only"; }
        return "Sound + Vibrate";
    }
}
