// AlarmStorage.mc
// Handles saving and loading all alarm settings using persistent storage.
// All methods are static so you can call them from anywhere with AlarmStorage.getX().

import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Day bitmask constants (bit 0 = Sunday, bit 1 = Monday, ... bit 6 = Saturday)
// Matches Garmin's day_of_week numbering (1=Sun ... 7=Sat) shifted to 0-indexed bits.
const DAY_SUN = 0x01;  // 0b0000001
const DAY_MON = 0x02;  // 0b0000010
const DAY_TUE = 0x04;  // 0b0000100
const DAY_WED = 0x08;  // 0b0001000
const DAY_THU = 0x10;  // 0b0010000
const DAY_FRI = 0x20;  // 0b0100000
const DAY_SAT = 0x40;  // 0b1000000

// Alert mode constants
const MODE_VIBE_AND_SOUND = 0;
const MODE_SOUND_ONLY     = 1;
const MODE_VIBE_ONLY      = 2;

(:background)
class AlarmStorage {

    // ── Getters ────────────────────────────────────────────────────────────────

    static function getAlarmHour() as Number {
        var v = Application.Storage.getValue("alarmHour");
        return (v != null) ? v : 7;
    }

    static function getAlarmMinute() as Number {
        var v = Application.Storage.getValue("alarmMinute");
        return (v != null) ? v : 30;
    }

    // Returns a bitmask of which days the alarm is active.
    // Default: Mon–Fri (0b0111110 = 62)
    static function getAlarmDays() as Number {
        var v = Application.Storage.getValue("alarmDays");
        return (v != null) ? v : (DAY_MON | DAY_TUE | DAY_WED | DAY_THU | DAY_FRI);
    }

    static function isAlarmEnabled() as Boolean {
        var v = Application.Storage.getValue("alarmEnabled");
        return (v != null) ? v : false;
    }

    // 0 = vibe+sound, 1 = sound only, 2 = vibe only
    static function getAlarmMode() as Number {
        var v = Application.Storage.getValue("alarmMode");
        return (v != null) ? v : MODE_VIBE_AND_SOUND;
    }

    // How many minutes before the scheduled alarm to start monitoring sleep.
    static function getWindowMinutes() as Number {
        var v = Application.Storage.getValue("windowMins");
        return (v != null) ? v : 45;
    }

    // ── Setters ────────────────────────────────────────────────────────────────

    static function saveAlarmHour(hour as Number) as Void {
        Application.Storage.setValue("alarmHour", hour);
    }

    static function saveAlarmMinute(minute as Number) as Void {
        Application.Storage.setValue("alarmMinute", minute);
    }

    static function saveAlarmDays(days as Number) as Void {
        Application.Storage.setValue("alarmDays", days);
    }

    static function setAlarmEnabled(enabled as Boolean) as Void {
        Application.Storage.setValue("alarmEnabled", enabled);
    }

    static function saveAlarmMode(mode as Number) as Void {
        Application.Storage.setValue("alarmMode", mode);
    }

    static function saveWindowMinutes(minutes as Number) as Void {
        Application.Storage.setValue("windowMins", minutes);
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    // Returns true if today is one of the configured alarm days.
    static function isAlarmDay() as Boolean {
        var days = getAlarmDays();
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        // Garmin day_of_week: 1=Sunday, 2=Monday, ..., 7=Saturday
        // Shift to 0-indexed bit: bit 0 = Sun, bit 1 = Mon, etc.
        var bit = 1 << (today.day_of_week - 1);
        return (days & bit) != 0;
    }

    // Returns the alarm time as total minutes since midnight (e.g. 7:30 → 450).
    static function getAlarmTotalMinutes() as Number {
        return getAlarmHour() * 60 + getAlarmMinute();
    }

    // Resets the per-day monitoring state (call after alarm fires or day changes).
    static function resetDailyState() as Void {
        Application.Storage.setValue("monitorState", 0);
        Application.Storage.setValue("bestScore", null);
        Application.Storage.setValue("lastAlarmTime", null);
    }
}