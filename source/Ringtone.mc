// Ringtone.mc
// Ringtones are Garmin's BUILT-IN alarm tones.
//
// We originally rebuilt the user's .wav files as custom ToneProfile sequences,
// but the FR265S does not play them, so that approach is gone. Connect IQ apps
// cannot play audio files at all, and custom tone profiles need a tone generator
// this watch doesn't expose - the only sounds available are Garmin's presets.
//
// The list is built at RUNTIME and only includes tones the device actually has
// (checked with `Attention has :TONE_X`), so nothing can be selected that the
// watch can't play.

import Toybox.Attention;
import Toybox.Lang;

class Ringtone {

    // Cached list of [displayName, toneConstant] for this device.
    private static var _list as Array? = null;

    private static function build() as Array {
        if (_list != null) { return _list as Array; }
        var out = [];

        // Each entry is only added if this device supports that tone.
        if (Attention has :TONE_ALARM)          { out.add(["Alarm",      Attention.TONE_ALARM]); }
        if (Attention has :TONE_LOUD_BEEP)      { out.add(["Loud Beep",  Attention.TONE_LOUD_BEEP]); }
        if (Attention has :TONE_ALERT_HI)       { out.add(["Alert High", Attention.TONE_ALERT_HI]); }
        if (Attention has :TONE_ALERT_LO)       { out.add(["Alert Low",  Attention.TONE_ALERT_LO]); }
        if (Attention has :TONE_INTERVAL_ALERT) { out.add(["Interval",   Attention.TONE_INTERVAL_ALERT]); }
        if (Attention has :TONE_CANARY)         { out.add(["Canary",     Attention.TONE_CANARY]); }
        if (Attention has :TONE_ATTENTION)      { out.add(["Attention",  Attention.TONE_ATTENTION]); }
        if (Attention has :TONE_TIME_ALERT)     { out.add(["Time Alert", Attention.TONE_TIME_ALERT]); }
        if (Attention has :TONE_MSG)            { out.add(["Message",    Attention.TONE_MSG]); }
        if (Attention has :TONE_SUCCESS)        { out.add(["Success",    Attention.TONE_SUCCESS]); }
        if (Attention has :TONE_LAP)            { out.add(["Lap",        Attention.TONE_LAP]); }
        if (Attention has :TONE_START)          { out.add(["Start",      Attention.TONE_START]); }

        // Absolute fallback so the list is never empty.
        if (out.size() == 0) { out.add(["Alarm", Attention.TONE_ALARM]); }

        _list = out;
        return out;
    }

    // Display names, for the Ringtone menu.
    static function names() as Array {
        var l = build();
        var out = [];
        for (var i = 0; i < l.size(); i++) {
            out.add((l[i] as Array)[0]);
        }
        return out;
    }

    static function count() as Number { return build().size(); }

    static function nameAt(index as Number) as String {
        var l = build();
        var i = index;
        if (i < 0 || i >= l.size()) { i = 0; }
        return (l[i] as Array)[0] as String;
    }

    // Plays ringtone `index` once. The ringing screen calls this on a repeating
    // timer, which is what makes it loop until you snooze or wake.
    static function play(index as Number) as Void {
        var l = build();
        var i = index;
        if (i < 0 || i >= l.size()) { i = 0; }
        try {
            // No cast here: these are Attention.Tone values, not Numbers.
            var entry = l[i] as Array;
            Attention.playTone(entry[1]);
        } catch (e) {
            try {
                Attention.playTone(Attention.TONE_ALARM);
            } catch (e2) {
            }
        }
    }
}
