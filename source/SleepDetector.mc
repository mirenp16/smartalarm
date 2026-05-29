// SleepDetector.mc
// Estimates how "light" the user's sleep is right now using a 0–100 score.
// Score 0  = deep sleep (do NOT wake)
// Score 100 = very light sleep / about to wake naturally (ideal to alarm)
//
// Method: combines two signals:
//   1. Heart-rate variability (HRV proxy) — higher variance = lighter sleep
//   2. Recent movement — more movement = lighter sleep
//
// Why this works: During deep sleep your HR is slow and very steady, and you
// barely move. As you cycle into lighter sleep your HR rises slightly and
// becomes more irregular, and you shift position more often.

import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.Sensor;
import Toybox.Time;

(:background)
class SleepDetector {

    // ── Public API ─────────────────────────────────────────────────────────────

    // Returns 0–100. Call this from the background service every 5 minutes.
    static function getLightnessScore() as Number {
        var hrScore  = _heartRateScore();
        var movScore = _movementScore();

        // Weighted blend: HR signal is more reliable than movement for sleep staging
        var score = (hrScore * 0.65 + movScore * 0.35).toNumber();
        return _clamp(score, 0, 100);
    }

    // ── Private helpers ────────────────────────────────────────────────────────

    // Analyses the standard deviation of heart rate samples over the last 10 min.
    // Low stdDev = steady = deep sleep. High stdDev = variable = light sleep.
    private static function _heartRateScore() as Number {
        var iter = SensorHistory.getHeartRateHistory({
            :period => new Time.Duration(10 * 60),  // last 10 minutes
            :order  => SensorHistory.ORDER_NEWEST_FIRST
        });

        // Collect valid HR samples (ignore 0 / null which means no reading)
        var samples = [] as Array<Number>;
        var item = iter.next();
        while (item != null && samples.size() < 30) {
            var hr = item.data;
            if (hr != null && hr > 25 && hr < 200) {
                samples.add(hr);
            }
            item = iter.next();
        }

        if (samples.size() < 4) { return 50; }  // Not enough data

        // Mean
        var sum = 0;
        for (var i = 0; i < samples.size(); i++) { sum += samples[i]; }
        var mean = sum.toFloat() / samples.size();

        // Standard deviation
        var variance = 0.0;
        for (var i = 0; i < samples.size(); i++) {
            var d = (samples[i].toFloat() - mean);
            variance += d * d;
        }
        variance /= samples.size();
        var stdDev = Math.sqrt(variance.toDouble()).toFloat();

        // Map stdDev to score:
        // ~0–2 bpm stdDev = deep sleep → score ~0–25
        // ~3–5 bpm stdDev = light sleep → score ~35–65
        // ~6–10+ bpm stdDev = very light / almost awake → score ~75–100
        var score = (stdDev / 9.0 * 100.0).toNumber();
        return _clamp(score, 0, 100);
    }

    // Checks the accelerometer for recent movement magnitude.
    // A single instant reading — if the user just moved, score goes up.
    private static function _movementScore() as Number {
        if (!(Toybox has :Sensor)) { return 50; }

        var info = Sensor.getInfo();
        if (info == null || !(info has :accel) || info.accel == null) {
            return 50;
        }

        var accel = info.accel;  // [x, y, z] in milli-g
        if (accel.size() < 3)   { return 50; }

        // Total magnitude of the accel vector.
        // At rest = ~1000 milli-g (gravity). Movement adds to this.
        var mag = Math.sqrt(
            (accel[0] * accel[0] +
             accel[1] * accel[1] +
             accel[2] * accel[2]).toDouble()
        ).toFloat();

        // Deviation from pure gravity (Math.abs removed in SDK 9, use ternary)
        var diff = mag - 1000.0;
        var movement = (diff >= 0.0 ? diff : -diff).toFloat();

        // Map 0–400 milli-g range to 0–100 score
        var score = (movement / 400.0 * 100.0).toNumber();
        return _clamp(score, 0, 100);
    }

    private static function _clamp(val as Number, lo as Number, hi as Number) as Number {
        if (val < lo) { return lo; }
        if (val > hi) { return hi; }
        return val;
    }
}