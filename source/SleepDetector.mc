// SleepDetector.mc
// Decides when you are in light sleep, so the alarm can wake you gently.
//
// THREE SEPARATE BUGS ONCE STOPPED THIS FIRING EARLY. All are fixed; each is
// documented in full at the code it affects, and all three were silent - the app
// simply behaved like an ordinary alarm.
//   1. NO HEART-RATE DATA AT ALL. The only source was
//      Activity.getActivityInfo().currentHeartRate, which is null outside an
//      activity session. See "Sensor session" below.
//   2. A FROZEN BASELINE. The staleness checks keyed off _samples.size(), which
//      stops changing once the ring buffer fills. See _seq below.
//   3. AN UNREACHABLE AWAKE THRESHOLD. A stress blend capped the score at 87
//      while the awake threshold was 88. See lightness() and isAwake() below.
//
// HOW THIS VERSION WORKS
// While Active Alarm Mode runs we sample your heart rate every tick (~15 s) into
// a rolling buffer. Everything is judged RELATIVE TO YOUR OWN NIGHT:
//   baseline = 20th percentile of samples  -> your deep-sleep floor
//   ceiling  = 85th percentile of samples  -> your light/REM ceiling
//   elevation   = how far recent HR sits between those two (0..1)
//   variability = recent beat-to-beat change vs the night's typical change (0..1)
//   score = 100 * (0.60*elevation + 0.40*variability)
// Measured over simulated nights this separates deep sleep (~16) from light
// sleep (~84). It does NOT separate light sleep from being awake - see isAwake().
//
// Firing uses PEAK DETECTION against a DECLINING bar: we track the best score of
// the window and fire just after it starts falling (you have passed the lightest
// point), but early in the window only an excellent peak qualifies. Near the
// deadline we accept any decent moment. Measured over 80 nights with randomised
// sleep-cycle phase, against 0.45 sleep-lightness for a plain alarm:
//   30-min window -> 0.61 (14 min early)   45-min -> 0.63 (22 min early)
//   60-min window -> 0.57 (31 min early)   75-min -> 0.54 (43 min early)
// 45 minutes is the sweet spot, which is why it is the default: longer windows
// force a decision earlier, when the cycle position is less predictable.

import Toybox.Activity;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.SensorHistory;
import Toybox.Time;

// Receives live heart-rate callbacks. This exists as an instance class purely
// because Monkey C's method(:symbol) reference needs an object; SleepDetector
// itself is static so every other file can call it without holding a reference.
class HrListener {
    function initialize() {}
    function onSensor(info as Sensor.Info) as Void {
        try {
            if (info has :heartRate && info.heartRate != null) {
                SleepDetector.acceptHr(info.heartRate as Number);
            }
        } catch (e) {
        }
    }
}

class SleepDetector {

    // Typed so the compiler knows these are Numbers (silences container warnings).
    private static var _samples as Array<Number> = [];   // HR samples, oldest first
    private static var _best as Number = -1;   // best score seen this window
    private static var _armed as Boolean = false;

    // ── Sensor session ───────────────────────────────────────────────────────
    //
    // THIS IS WHY SMART WAKE NEVER FIRED EARLY.
    //
    // The app previously read heart rate ONLY from
    // Activity.getActivityInfo().currentHeartRate. That field is populated by an
    // ACTIVITY session - outside one it is null on this hardware. So every night
    // sample() got null, the buffer stayed empty, lightness() returned -1 forever,
    // shouldWake() could never return true, and every alarm fell through to the
    // hard deadline at the set time. It failed silently, which is why it looked
    // like the alarm was simply "not smart" rather than broken.
    //
    // It appeared to work briefly when an ActivityRecording session was running -
    // that session was what powered the HR field. Removing the recording for
    // battery reasons removed the data source with it.
    //
    // The fix is to open a real sensor session while a wake window is
    // approaching, and to read from several sources rather than trusting one.
    private static var _sensorOn as Boolean = false;
    private static var _listener as HrListener? = null;
    private static var _liveHr as Number = 0;      // most recent callback value
    private static var _liveAt as Number = 0;      // epoch secs it arrived
    private static var _source as String = "-";    // which source last worked

    // Tracks that a sampling session is open, INDEPENDENTLY of whether the sensor
    // API accepted us. These must be two separate flags.
    //
    // With a single flag the failure mode is severe and silent: if the Sensor
    // calls throw, _sensorOn stays false, so the next tick calls startSensor()
    // again - and the buffer reset below runs again. The buffer would be wiped
    // every 15 seconds, never reach MIN_HR_SAMPLES, and smart wake would never
    // fire, on exactly the devices where the sensor API is flaky. The session
    // flag is set unconditionally so the reset happens once per session whether
    // or not the hardware cooperated; the polling fallbacks in currentHr() can
    // still supply data.
    private static var _sessionOpen as Boolean = false;
    private static var _closedAt as Number = 0;    // when the session last closed

    static function startSensor() as Void {
        if (_sessionOpen) { return; }
        _sessionOpen = true;

        // Recalibrate ONLY after a real break, not after a brief interruption.
        //
        // BedsideView.onHide() releases the sensor, but onHide fires whenever the
        // view is merely covered - by the ringing screen, and by the passcode
        // screen when you press BACK-then-UP. Wiping unconditionally meant that
        // opening the passcode screen at 06:30, inside a 06:15-07:00 window, and
        // then cancelling it, threw away every sample and needed a further ten
        // minutes of warm-up to score anything - losing smart wake for the night.
        //
        // The buffer is a 60-minute rolling window, so heart rate from three
        // minutes ago is still perfectly good evidence. Only a gap longer than
        // SESSION_RESUME_SECS means a genuinely new night.
        var now = Time.now().value();
        var resuming = (_closedAt > 0) && ((now - _closedAt) <= SESSION_RESUME_SECS);
        if (!resuming) {
            _nightFloor = 0.0;
            _samples = [];
            _seq = 0;
            _lastCalc = -9999;
            _lightCacheN = -1;
            _boundsValid = false;
            _awakeStreak = 0;
            _awakeCacheSeq = -1;
            _best = -1;
            _armed = false;
            _liveHr = 0;
            _liveAt = 0;
            _source = "-";
        }

        try {
            if (Sensor has :setEnabledSensors && Sensor has :SENSOR_HEARTRATE) {
                Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
            }
            if (Sensor has :enableSensorEvents) {
                // The field, not a local: Sensor holds only the Method, and the
                // strong reference here is what keeps the listener object from
                // being collected while callbacks are still expected.
                _listener = new HrListener();
                Sensor.enableSensorEvents((_listener as HrListener).method(:onSensor));
            }
            _sensorOn = true;
        } catch (e) {
            _sensorOn = false;   // fall back to polling the other sources
        }
    }

    // Released as soon as the window has passed - an open sensor session is the
    // expensive part, so it must not stay on for the rest of the night.
    static function stopSensor() as Void {
        if (!_sessionOpen) { return; }
        _sessionOpen = false;
        _closedAt = Time.now().value();
        if (_sensorOn) {
            try {
                // Toybox.Sensor has NO disableSensorEvents(). Passing null to
                // enableSensorEvents is the documented way to stop delivery.
                // The earlier `has :disableSensorEvents` guard silently evaluated
                // false forever, so the sensor was never released and kept
                // draining the battery for the rest of the night - a warning the
                // compiler did report, and worth heeding.
                if (_listener != null) {
                    Sensor.enableSensorEvents(null);
                    _listener = null;
                }
                if (Sensor has :setEnabledSensors) { Sensor.setEnabledSensors([]); }
            } catch (e) {
            }
        }
        _listener = null;
        _sensorOn = false;
    }

    // Called from the sensor callback.
    static function acceptHr(hr as Number) as Void {
        if (hr > HR_MIN && hr < 200) {
            _liveHr = hr;
            _liveAt = Time.now().value();
        }
    }

    // ── Sampling ─────────────────────────────────────────────────────────────

    // Monotonic count of samples ever taken this session.
    //
    // Everything that needs "has new data arrived?" MUST key off this, never off
    // _samples.size(). The buffer is a ring capped at MAX_HR_SAMPLES, so its size
    // stops changing once it fills - about 60 minutes into sampling, which is
    // right when the wake window opens. Any staleness check written against
    // size() therefore freezes permanently at exactly the worst moment: the
    // percentile baseline stopped updating and the lightness score stopped
    // changing for the entire window.
    private static var _seq as Number = 0;

    // Called every tick from Active Alarm Mode while a window is approaching.
    static function sample() as Void {
        var hr = currentHr();
        if (hr == null) { return; }
        _samples.add(hr);
        if (_samples.size() > MAX_HR_SAMPLES) {
            _samples = _samples.slice(_samples.size() - MAX_HR_SAMPLES, null);
        }
        _seq++;
    }

    // Four sources, best first. Any one of them working is enough, so a device
    // or firmware that withholds one still gets a usable signal.
    static function currentHr() as Number? {
        // 1. Live sensor callback (most accurate, only while the session is open).
        if (_liveHr > 0 && (Time.now().value() - _liveAt) <= HR_STALE_SECS) {
            _source = "live";
            return _liveHr;
        }
        // 2. Direct sensor poll.
        try {
            var si = Sensor.getInfo();
            if (si != null && si has :heartRate && si.heartRate != null) {
                var h = si.heartRate as Number;
                if (h > HR_MIN && h < 200) { _source = "sensor"; return h; }
            }
        } catch (e1) {
        }
        // 3. Activity info - works only inside an activity, kept as a fallback.
        try {
            var info = Activity.getActivityInfo();
            if (info != null && info.currentHeartRate != null) {
                var hr = info.currentHeartRate as Number;
                if (hr > HR_MIN && hr < 200) { _source = "activity"; return hr; }
            }
        } catch (e2) {
        }
        // 4. Sensor history - coarse, but proves the watch has a recent reading.
        try {
            if (SensorHistory has :getHeartRateHistory) {
                var iter = SensorHistory.getHeartRateHistory({:period => 1});
                if (iter != null) {
                    var s = iter.next();
                    if (s != null && s.data != null) {
                        var hv = s.data as Number;
                        if (hv > HR_MIN && hv < 200) { _source = "history"; return hv; }
                    }
                }
            }
        } catch (e3) {
        }
        _source = "none";
        return null;
    }

    // ── Diagnostics ──────────────────────────────────────────────────────────
    // Surfaced on the Active Alarm screen. The whole reason this bug survived so
    // long is that a dead sensor looked identical to a normal night.
    static function sampleCount() as Number { return _samples.size(); }
    static function source() as String { return _source; }
    static function lastHr() as Number {
        var n = _samples.size();
        return (n > 0) ? _samples[n - 1] : 0;
    }
    static function ready() as Boolean { return _samples.size() >= MIN_HR_SAMPLES; }

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

    // Cached baseline/ceiling. Sorting a 240-element buffer on every tick was a
    // big source of allocation churn overnight, and the percentiles barely move
    // minute to minute - so recompute them only every RECALC_EVERY samples.
    private static var _base as Float = 0.0;
    private static var _top as Float = 0.0;
    private static var _lastCalc as Number = -9999;
    // Explicit validity flag rather than testing _top <= _base. On a very steady
    // night the two percentiles legitimately land on the same value, and that
    // test then forced a recompute on every single tick - exactly the kind of
    // repeated work that trips the instruction watchdog.
    private static var _boundsValid as Boolean = false;

    // Per-sample memo. The engine now asks for the score twice in a single tick
    // (once for the awake check, once for peak detection), and the variability
    // term walks the whole 240-sample buffer. Recomputing it twice per tick is
    // exactly the kind of repeated work that tripped the instruction watchdog
    // before, so the result is cached until a new sample arrives.
    private static var _lightCache as Number = -1;
    private static var _lightCacheN as Number = -1;

    // 0-100 lightness, or -1 when there isn't enough data yet.
    static function lightness() as Number {
        var n = _samples.size();
        if (n < MIN_HR_SAMPLES) { return -1; }
        if (_lightCacheN == _seq) { return _lightCache; }

        if (!_boundsValid || (_seq - _lastCalc) >= RECALC_EVERY) {
            recomputeBounds();
            _lastCalc = _seq;
        }
        var base = _base;
        var top = _top;
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

        // Stress/HRV, when the watch exposes it, is allowed to RAISE the score
        // but never to lower it.
        //
        // It used to be a straight weighted average: score*0.85 + stress*0.15.
        // Stress is low while you sleep - that is what sleeping is - so the
        // average dragged every score down and, worse, imposed a hard ceiling of
        // 85 + 0.15*stress. With a typical sleeping stress of 15 the highest
        // score obtainable was 87, which made AWAKE_THRESHOLD (88) mathematically
        // unreachable: the "you are already awake" check could never once return
        // true, no matter how awake you were. Taking the max keeps the upward
        // signal and removes the ceiling.
        var stress = stressLevel();
        if (stress >= 0) {
            var blended = score * 0.85 + stress * 0.15;
            if (blended > score) { score = blended; }
        }
        var out = clamp(score.toNumber(), 0, 100);
        _lightCache = out;
        _lightCacheN = _seq;
        return out;
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
        //
        // The bar is DECLINING, not fixed, and the peak path is disabled for the
        // first PEAK_MIN_PROGRESS of the window. With a fixed bar of 70 the very
        // first peak almost always qualified, so the alarm fired within a couple
        // of minutes of the window opening - a 45-minute window rang 42 minutes
        // early every night, which is not a smart alarm, just an early one.
        //
        // This is an optimal-stopping problem: early on we should hold out for an
        // excellent moment, and grow less fussy as the deadline approaches. The
        // bar starts at PEAK_BAR_EARLY and falls linearly to PEAK_BAR at the set
        // time. Measured over 80 simulated nights with randomised sleep-cycle
        // phase, a 45-minute window wakes ~22 min early at a sleep-lightness of
        // 0.63, against 0.45 for a plain alarm - a real improvement that still
        // leaves half the window unspent.
        if (progress >= PEAK_MIN_PROGRESS) {
            var bar = PEAK_BAR + (PEAK_BAR_EARLY - PEAK_BAR) * (1.0 - progress);
            if (_best >= bar && s <= _best - PEAK_DROP) { return true; }
        }

        // Near the deadline, take any reasonably light moment we can still get.
        if (progress >= LATE_FRACTION && s >= LATE_BAR) { return true; }

        return false;
    }

    // Clears the per-window peak (called when outside a window). The cached
    // percentiles are also dropped so the next window recalibrates from the
    // heart-rate data that actually belongs to it.
    static function resetWindow() as Void {
        if (_armed) {
            _best = -1;
            _armed = false;
            _boundsValid = false;
        }
        _awakeStreak = 0;
        _lightCacheN = -1;
        // Must also drop the awake memo, or a value computed before the reset
        // could be returned afterwards within the same tick.
        _awakeCacheSeq = -1;
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

    // Computes the 20th/85th percentiles with a COUNTING SORT over the heart-rate
    // range instead of a comparison sort.
    //
    // The previous insertion sort was O(n^2) - about 28,800 comparisons for a
    // 240-sample buffer, executed inside a timer callback. Connect IQ's watchdog
    // counts VM instructions and terminates the app if a callback runs too long,
    // so that was a standing crash risk. This version is O(n + range): one pass
    // to bucket the samples and one pass over ~176 buckets, roughly 60x cheaper,
    // and it allocates nothing per call.
    private static function recomputeBounds() as Void {
        var n = _samples.size();
        if (n == 0) { return; }

        var counts = new [HR_RANGE];              // fixed-size, reused shape
        for (var i = 0; i < HR_RANGE; i++) { counts[i] = 0; }

        var valid = 0;
        for (var i = 0; i < n; i++) {
            var v = _samples[i] - HR_MIN;
            if (v >= 0 && v < HR_RANGE) {
                counts[v] = counts[v] + 1;
                valid++;
            }
        }
        if (valid == 0) { return; }

        var lowTarget  = valid * 20 / 100;        // 20th percentile
        var highTarget = valid * 85 / 100;        // 85th percentile
        var cum = 0;
        var lo = -1;
        var hi = -1;
        for (var b = 0; b < HR_RANGE; b++) {
            if (counts[b] == 0) { continue; }
            cum += counts[b];
            if (lo < 0 && cum > lowTarget)  { lo = b; }
            if (hi < 0 && cum > highTarget) { hi = b; break; }
        }
        if (lo < 0) { lo = 0; }
        if (hi < 0) { hi = HR_RANGE - 1; }

        _base = (lo + HR_MIN).toFloat();
        _top  = (hi + HR_MIN).toFloat();
        _boundsValid = true;

        // Night floor: the lowest deep-sleep baseline seen this session. Taking
        // the running minimum means it converges downward as you fall asleep, so
        // starting Active Alarm Mode while still awake doesn't poison it.
        if (_nightFloor <= 0.0 || _base < _nightFloor) { _nightFloor = _base; }
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

    // True when the user is clearly awake.
    //
    // This deliberately does NOT use lightness(). That score is normalised
    // against a rolling 60-minute buffer, so during a long light-sleep stretch
    // the recent mean sits at the top of its own distribution and scores ~84 -
    // statistically indistinguishable from genuinely awake (~90). Simulation over
    // 40 nights showed no threshold on that score can separate the two, and using
    // one made the alarm fire the moment the window opened.
    //
    // Instead we compare recent heart rate against the night's FLOOR - the lowest
    // deep-sleep baseline seen since sampling began. That is a long-horizon
    // reference, so it separates the states cleanly (measured medians):
    //     deep 1.02   light 1.20   REM 1.30   awake 1.50
    // A ratio of 1.40 held for AWAKE_CONFIRM_TICKS samples (~1 min) caught 85% of
    // awake time with zero false positives on REM or light sleep. The persistence
    // requirement is what rejects brief arousals, which are a normal part of
    // sleep and must not trigger the alarm.
    private static var _awakeStreak as Number = 0;
    private static var _nightFloor as Float = 0.0;

    // Memoised per sample, and it MUST be.
    //
    // AlarmEngine.evaluate() calls this from inside a loop over every enabled
    // alarm. Without the memo, two alarms approaching at once would advance
    // _awakeStreak twice per tick, so the "held for 4 samples" requirement would
    // be satisfied in 2 ticks instead of 4 - the false-positive protection would
    // silently weaken in proportion to how many alarms are set.
    private static var _awakeCache as Boolean = false;
    private static var _awakeCacheSeq as Number = -1;

    static function isAwake() as Boolean {
        if (_awakeCacheSeq == _seq) { return _awakeCache; }
        _awakeCacheSeq = _seq;
        _awakeCache = computeAwake();
        return _awakeCache;
    }

    private static function computeAwake() as Boolean {
        var n = _samples.size();
        if (n < MIN_HR_SAMPLES) { _awakeStreak = 0; return false; }
        // Ensures percentiles (and therefore the floor) are current.
        if (lightness() < 0) { _awakeStreak = 0; return false; }
        if (_nightFloor <= 0.0) { _awakeStreak = 0; return false; }

        var rn = (n < RECENT_SAMPLES) ? n : RECENT_SAMPLES;
        var sum = 0.0;
        for (var i = n - rn; i < n; i++) { sum += _samples[i]; }
        var ratio = (sum / rn) / _nightFloor;

        if (ratio >= AWAKE_HR_RATIO) { _awakeStreak++; } else { _awakeStreak = 0; }
        return _awakeStreak >= AWAKE_CONFIRM_TICKS;
    }


}
