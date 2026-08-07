// Ringtone.mc
// Plays a ringtone through the watch's buzzer using Attention.ToneProfile, which
// takes a list of (frequency, duration) pairs. The sequences in Ringtones.mc were
// derived from the user's .wav files.
//
// Every call is wrapped in try/catch and falls back to Garmin's built-in alarm
// tone, so a device without a tone generator can never crash the alarm.

import Toybox.Attention;
import Toybox.Lang;

class Ringtone {

    // Plays ringtone `index` once. The ringing screen calls this on a repeating
    // timer, which is what makes it loop continuously until you snooze or wake.
    static function play(index as Number) as Void {
        var i = index;
        if (i < 0 || i >= RINGTONE_DATA.size()) { i = 0; }

        try {
            if (Attention has :ToneProfile) {
                var seq = RINGTONE_DATA[i] as Array;
                var profile = [];
                for (var n = 0; n < seq.size(); n++) {
                    var note = seq[n] as Array;
                    var freq = note[0] as Number;
                    var ms   = note[1] as Number;
                    // A frequency of 0 is a rest; the tone generator wants a real
                    // frequency, so use an inaudible one to create the gap.
                    if (freq <= 0) { freq = 20; }
                    profile.add(new Attention.ToneProfile(freq, ms));
                }
                if (profile.size() > 0) {
                    Attention.playTone({:toneProfile => profile, :repeatCount => 1});
                    return;
                }
            }
        } catch (e) {
        }

        // Fallback: the standard alarm tone.
        try {
            Attention.playTone(Attention.TONE_ALARM);
        } catch (e2) {
        }
    }

    // Total length of a ringtone in milliseconds (used to time the repeat).
    static function durationMs(index as Number) as Number {
        var i = index;
        if (i < 0 || i >= RINGTONE_DATA.size()) { i = 0; }
        var seq = RINGTONE_DATA[i] as Array;
        var total = 0;
        for (var n = 0; n < seq.size(); n++) {
            total += (seq[n] as Array)[1] as Number;
        }
        return total;
    }
}
