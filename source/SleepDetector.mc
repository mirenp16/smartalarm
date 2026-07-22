// SleepDetector.mc
// Estimates how "light" the user's sleep is right now as a 0–100 score.
//   0   = deep sleep (do NOT wake)
//   100 = very light / basically awake (ideal moment to wake)
//
// Garmin does not expose real-time sleep STAGES to third-party apps, so the most
// accurate signal available is built live from two sensors:
//   1. Heart-rate variability  — steady HR = deep sleep, variable HR = light
//   2. Body movement           — still = deep, moving = light/awake
//
// Annotated (:background) because the service calls it while the app is closed.

import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.Sensor;
import Toybox.Time;

(:background)
class SleepDetector {

    // Blended 0–100 lightness score. Call every 5 min from the service.
    static function lightness() as Number {
        var hr  = heartRateScore();
        var mov = movementScore();
        // HR is the more reliable sleep-stage signal, so weight it higher.
        var score = (hr * 0.65 + mov * 0.35).toNumber();
        return clamp(score, 0, 100);
    }

    // Standard deviation of the last 10 minutes of heart-rate samples.
    // Low deviation = steady = deep sleep; high deviation = light sleep.
    static function heartRateScore() as Number {
        var iter = SensorHistory.getHeartRateHistory({
            :period => new Time.Duration(10 * 60),
            :order  => SensorHistory.ORDER_NEWEST_FIRST
        });

        var samples = [];
        var item = (iter != null) ? iter.next() : null;
        while (item != null && samples.size() < 30) {
            var hr = item.data;
            if (hr != null && hr > 25 && hr < 200) {
                samples.add(hr);
            }
            item = iter.next();
        }

        if (samples.size() < 4) { return 50; }  // not enough data -> neutral

        // Mean
        var sum = 0;
        for (var i = 0; i < samples.size(); i++) { sum += samples[i]; }
        var mean = sum.toFloat() / samples.size();

        // Standard deviation
        var variance = 0.0;
        for (var i = 0; i < samples.size(); i++) {
            var d = samples[i].toFloat() - mean;
            variance += d * d;
        }
        variance /= samples.size();
        var stdDev = Math.sqrt(variance.toDouble()).toFloat();

        // Map deviation to score: ~0-2 bpm deep, ~3-5 light, ~6-9+ almost awake.
        var score = (stdDev / 9.0 * 100.0).toNumber();
        return clamp(score, 0, 100);
    }

    // Instantaneous accelerometer magnitude vs gravity. Any real movement pushes
    // the score up (light sleep / awake).
    static function movementScore() as Number {
        var info = Sensor.getInfo();
        if (info == null || info.accel == null) { return 50; }

        var accel = info.accel;  // [x, y, z] in milli-g
        if (accel.size() < 3) { return 50; }

        var mag = Math.sqrt(
            (accel[0] * accel[0] +
             accel[1] * accel[1] +
             accel[2] * accel[2]).toDouble()
        ).toFloat();

        // Deviation from ~1000 milli-g gravity (Math.abs was removed in SDK 9).
        var diff = mag - 1000.0;
        var movement = (diff >= 0.0) ? diff : -diff;

        var score = (movement / 400.0 * 100.0).toNumber();
        return clamp(score, 0, 100);
    }

    // True if the user looks clearly awake/active right now. Used before the wake
    // window opens: if awake, we skip smart detection and fire on the exact time.
    static function isAwake() as Boolean {
        return lightness() >= AWAKE_THRESHOLD;
    }

    static function clamp(v as Number, lo as Number, hi as Number) as Number {
        if (v < lo) { return lo; }
        if (v > hi) { return hi; }
        return v;
    }
}
