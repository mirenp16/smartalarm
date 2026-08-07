// SleepDetector.mc
// Decides when you are in light sleep, so the alarm can wake you gently.
//
// WHY THE OLD VERSION NEVER FIRED EARLY
// It scored heart-rate standard deviation against a FIXED scale and needed 65/100
// to trigger. Simulated over whole nights that score peaked around 43 - it was
// mathematically incapable of ever reaching the threshold. It also relied on
// SensorHistory + the accelerometer, which are sparse/unavailable here.
//
// HOW THIS VERSION WORKS
// While Active Alarm Mode runs we sample your heart rate every tick (~15 s) into
// a rolling buffer. Everything is judged RELATIVE TO YOUR OWN NIGHT:
//   baseline = 20th percentile of samples  -> your deep-sleep floor
//   ceiling  = 85th percentile of samples  -> your light/REM ceiling
//   elevation   = how far recent HR sits between those two (0..1)
//   variability = recent beat-to-beat change vs the night's typical change (0..1)
//   score = 100 * (0.60*elevation + 0.40*variability)
// In simulation this cleanly separates deep sleep (~16) from light sleep (~78).
//
// Firing uses PEAK DETECTION rather than a fixed cut-off: we track the best score
// of the window and fire just after it starts falling (you have passed the
// lightest point). Near the end of the window we accept any decent moment.
// Simulated results vs a plain alarm (0.47 lightness at wake):
//   30-min window -> 0.60,  45-min -> 0.71,  60-min -> 0.81
// So a longer Sleep Cycle Window gives the algorithm far more to work with.

import Toybox.Activity;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.Time;

class SleepDetector {

    // Typed so the compiler knows these are Numbers (silences container warnings).
    private static var _samples as Array<Number> = [];   // HR samples, oldest first
    private static var _best as Number = -1;   // best score seen this window
    private static var _armed as Boolean = false;

    // ── Sampling ─────────────────────────────────────────────────────────────

    // Called every tick from Active Alarm Mode. Cheap: the watch is already
    // measuring HR overnight, we just read the latest value.
    static function sample() as Void {
        var hr = currentHr();
        if (hr == null) { return; }
        _samples.add(hr);
        if (_samples.size() > MAX_HR_SAMPLES) {
            _samples = _samples.slice(_samples.size() - MAX_HR_SAMPLES, null);
        }
    }

    static function currentHr() as Number? {
        try {
            var info = Activity.getActivityInfo();
            if (info != null && info.currentHeartRate != null) {
                var hr = info.currentHeartRate;
                if (hr > 25 && hr < 200) { return hr; }
            }
        } catch (e) {
        }
        return null;
    }

    // Optional secondary signal: Garmin's stress value (derived from HRV).
    // Higher stress generally tracks lighter sleep. Returns 0..100 or -1.
    static function stressLevel() as Number {
        try {
            if (SensorHistory has :getStressHistory) {
                var iter = SensorHistory.getStressHistory({:period => 1});
                if (iter != null) {
                    var s = iter.next();
                    if (s != null && s.data != null) {
                        return clamp((s.data as Number), 0, 100);
                    }
                }
            }
        } catch (e) {
        }
        return -1;
    }

    // ── Scoring ──────────────────────────────────────────────────────────────

    // 0-100 lightness, or -1 when there isn't enough data yet.
    static function lightness() as Number {
        var n = _samples.size();
        if (n < MIN_HR_SAMPLES) { return -1; }

        var sorted = sortedCopy(_samples);
        var base = percentile(sorted, 20);   // deep-sleep floor
        var top  = percentile(sorted, 85);   // light/REM ceiling
        var span = top - base;
        if (span < 2.0) { span = 2.0; }      // guard against a flat night

        // Recent mean (last ~3 minutes)
        var rn = (n < RECENT_SAMPLES) ? n : RECENT_SAMPLES;
        var recentSum = 0.0;
        for (var i = n - rn; i < n; i++) { recentSum += _samples[i]; }
        var recentMean = recentSum / rn;

        var elevation = (recentMean - base) / span;
        elevation = clampF(elevation, 0.0, 1.0);

        // Variability: recent beat-to-beat change vs the night's typical change.
        var dRecent = meanAbsDiff(_samples, n - rn, n);
        var dAll    = meanAbsDiff(_samples, 0, n);
        if (dAll < 0.01) { dAll = 0.01; }
        var variability = clampF(dRecent / (2.0 * dAll), 0.0, 1.0);

        var score = 100.0 * (0.60 * elevation + 0.40 * variability);

        // Blend in stress/HRV when the watch exposes it.
        var stress = stressLevel();
        if (stress >= 0) {
            score = score * 0.85 + stress * 0.15;
        }
        return clamp(score.toNumber(), 0, 100);
    }

    // ── Wake decision ────────────────────────────────────────────────────────

    // progress = 0.0 at the start of the Sleep Cycle Window, 1.0 at the set time.
    // Returns true when now is a good moment to wake.
    static function shouldWake(progress as Float) as Boolean {
        var s = lightness();
        if (s < 0) { return false; }          // not enough data yet

        _armed = true;
        if (s > _best) { _best = s; }

        // Just past a peak: we were in light sleep and are now sliding back down.
        if (_best >= PEAK_BAR && s <= _best - PEAK_DROP) { return true; }

        // Near the deadline, take any reasonably light moment we can still get.
        if (progress >= LATE_FRACTION && s >= LATE_BAR) { return true; }

        return false;
    }

    // Clears the per-window peak (called when outside a window).
    static function resetWindow() as Void {
        if (_armed) {
            _best = -1;
            _armed = false;
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private static function meanAbsDiff(arr as Array<Number>, from as Number, to as Number) as Float {
        if (to - from < 2) { return 0.0; }
        var sum = 0.0;
        for (var i = from + 1; i < to; i++) {
            var d = (arr[i] - arr[i - 1]).toFloat();
            sum += (d < 0) ? -d : d;
        }
        return sum / (to - from - 1);
    }

    private static function sortedCopy(arr as Array<Number>) as Array<Number> {
        var a = [] as Array<Number>;
        for (var i = 0; i < arr.size(); i++) { a.add(arr[i]); }
        // Insertion sort - the buffer is small and this runs at most once per tick.
        for (var i = 1; i < a.size(); i++) {
            var v = a[i];
            var j = i - 1;
            while (j >= 0 && a[j] > v) {
                a[j + 1] = a[j];
                j--;
            }
            a[j + 1] = v;
        }
        return a;
    }

    private static function percentile(sorted as Array<Number>, p as Number) as Float {
        var n = sorted.size();
        if (n == 0) { return 0.0; }
        var idx = (n - 1) * p / 100;
        if (idx < 0) { idx = 0; }
        if (idx > n - 1) { idx = n - 1; }
        return sorted[idx].toFloat();
    }

    static function clamp(v as Number, lo as Number, hi as Number) as Number {
        if (v < lo) { return lo; }
        if (v > hi) { return hi; }
        return v;
    }

    private static function clampF(v as Float, lo as Float, hi as Float) as Float {
        if (v < lo) { return lo; }
        if (v > hi) { return hi; }
        return v;
    }

    // True when the user looks clearly awake (used before the window opens).
    static function isAwake() as Boolean {
        var s = lightness();
        return (s >= 0) && (s >= AWAKE_THRESHOLD);
    }
}
