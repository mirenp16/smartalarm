// SleepDetector.mc
// Early-wake heuristic using heart-rate trends and recent steps. This does not
// read Garmin sleep stages or distinguish quiet wakefulness reliably.
// A rolling buffer supplies a 20th-percentile baseline and 85th-percentile
// ceiling. The score combines relative elevation (60%) with variability (40%).
// Fresh awake evidence may trigger at window opening; otherwise a recent peak
// and decline, or a qualifying late score, may trigger before the deadline.

import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Lang;
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
    private static var _bestSeq as Number = 0;

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
    private static var _listener as HrListener? = null;
    private static var _liveHr as Number = 0;      // most recent callback value
    private static var _liveAt as Number = 0;      // epoch secs it arrived

    // Mark the session open even if sensor registration fails: retrying the
    // session reset on every tick would erase data supplied by polling fallbacks.
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
        var now = AlarmClock.now().value();
        // A NEGATIVE gap means the clock moved backwards since we stamped it, so
        // the stamp belongs to a different epoch and tells us nothing. Treat it as
        // a real break and recalibrate rather than trusting a buffer we cannot
        // date. Every "now minus a stored timestamp" test in the app follows this
        // rule: negative is never "recent".
        var gap = now - _closedAt;
        var resuming = (_closedAt > 0) && (gap >= 0) && (gap <= SESSION_RESUME_SECS);
        if (!resuming) {
            resetSession();
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
        } catch (e) {
            // Polling remains available if sensor registration fails.
        }
    }

    // Released as soon as the window has passed - an open sensor session is the
    // expensive part, so it must not stay on for the rest of the night.
    static function stopSensor() as Void {
        if (!_sessionOpen) { return; }
        _sessionOpen = false;
        _closedAt = AlarmClock.now().value();
        try {
            // Passing null is the documented way to stop sensor callbacks.
            if (_listener != null) {
                Sensor.enableSensorEvents(null);
                _listener = null;
            }
        } catch (e) {
        }
        // Registration may have partially succeeded before throwing. Release
        // enabled sensors even if listener cleanup failed independently.
        try {
            if (Sensor has :setEnabledSensors) { Sensor.setEnabledSensors([]); }
        } catch (e2) { }
        _listener = null;
    }

    // Called from the sensor callback.
    static function acceptHr(hr as Number) as Void {
        if (hr > HR_MIN && hr < 200) {
            _liveHr = hr;
            _liveAt = AlarmClock.now().value();
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

    private static var _sampleAt as Number = 0;
    private static var _hasCurrent as Boolean = false;
    private static var _stepBase as Number = -1;
    private static var _stepAt as Number = 0;
    private static var _walkAt as Number = 0;

    private static function resetSession() as Void {
        _nightFloor = 0.0;
        _samples = [];
        _seq = 0;
        _sampleAt = 0;
        _hasCurrent = false;
        _lastCalc = -9999;
        _lightCacheN = -1;
        _boundsValid = false;
        _awakeStreak = 0;
        _awakeCacheSeq = -1;
        _awakeCache = false;
        _best = -1;
        _armed = false;
        _liveHr = 0;
        _liveAt = 0;
        _probeSamples = [];
        _probeSampleAt = 0;
        _stepBase = -1;
        _stepAt = 0;
        _walkAt = 0;
    }

    // Steps are a conservative additional signal for getting out of bed. A
    // single wrist movement is not enough. Counter resets (midnight) and gaps
    // start a new observation period rather than crediting old activity.
    static function recordSteps(steps as Number?, now as Number) as Void {
        if (steps == null || steps < 0) {
            _stepBase = -1;
            _walkAt = 0;
            return;
        }
        var age = now - _stepAt;
        if (_stepBase < 0 || steps < _stepBase || age < 0 || age > WALK_WINDOW_SECS) {
            if (age < 0 || steps < _stepBase) { _walkAt = 0; }
            _stepBase = steps;
            _stepAt = now;
            return;
        }
        if (steps - _stepBase >= WALK_MIN_STEPS) {
            _walkAt = now;
            _stepBase = steps;
            _stepAt = now;
        }
    }

    static function sample() as Void {
        var now = AlarmClock.now().value();
        try {
            var info = ActivityMonitor.getInfo();
            recordSteps(info.steps, now);
        } catch (e) {
            recordSteps(null, now);
        }
        recordHr(currentHr(), now);
    }

    // Keep a missing sample from reusing a previous awake result or old peak.
    // Recalibrate after long gaps; brief gaps retain the baseline, but break the
    // consecutive awake streak. Calibrate from the FIRST ten minutes, not only
    // when a scheduler first asks about wakefulness much later in the morning.
    static function recordHr(hr as Number?, now as Number) as Void {
        var gap = now - _sampleAt;
        if (_sampleAt > 0 && (gap < 0 || gap > HR_STALE_SECS)) {
            _awakeStreak = 0;
            resetWindow();
        }
        if (_sampleAt > 0 && (gap < 0 || gap > SESSION_RESUME_SECS)) {
            _samples = [];
            _nightFloor = 0.0;
            _boundsValid = false;
            _lastCalc = -9999;
            _awakeStreak = 0;
            resetWindow();
        }
        _seq++;
        _lightCacheN = -1;
        _awakeCacheSeq = -1;
        if (hr == null || hr <= HR_MIN || hr >= 200) {
            _hasCurrent = false;
            _awakeStreak = 0;
            _awakeCache = false;
            resetWindow();
            return;
        }
        _sampleAt = now;
        _hasCurrent = true;
        _samples.add(hr);
        if (_samples.size() > MAX_HR_SAMPLES) {
            _samples = _samples.slice(_samples.size() - MAX_HR_SAMPLES, null);
        }
        // Update once per sample, independently of the number of enabled alarms.
        _awakeCache = computeAwake();
        _awakeCacheSeq = _seq;
    }

    private static function fresh() as Boolean {
        var age = AlarmClock.now().value() - _sampleAt;
        return _hasCurrent && _sampleAt > 0 && age >= 0 && age <= HR_STALE_SECS;
    }

    // Test-only setup: absent from release builds. Decisions use production code.
    (:testSupport)
    static function resetForTest() as Void { resetSession(); }

    // Four sources, best first. Any one of them working is enough, so a device
    // or firmware that withholds one still gets a usable signal.
    //
    // EVERY source must be checked for FRESHNESS, not just for a value.
    // "What is my heart rate" and "what was the last heart rate this watch ever
    // recorded" are different questions, and the second one has an answer even
    // when the watch is sitting on a desk. Source 4 in particular reads the
    // all-day history, which survives taking the watch off, so without an age
    // check it reports a plausible number indefinitely.
    static function currentHr() as Number? {
        var nowSecs = AlarmClock.now().value();

        // 1. Live sensor callback (most accurate, only while the session is open).
        var liveAge = nowSecs - _liveAt;
        if (_liveHr > 0 && liveAge >= 0 && liveAge <= HR_STALE_SECS) {
            return _liveHr;
        }
        // 2. Direct sensor poll.
        try {
            var si = Sensor.getInfo();
            if (si != null && si has :heartRate && si.heartRate != null) {
                var h = si.heartRate as Number;
                if (h > HR_MIN && h < 200) { return h; }
            }
        } catch (e1) {
        }
        // 3. Activity info - works only inside an activity, kept as a fallback.
        try {
            var info = Activity.getActivityInfo();
            if (info != null && info.currentHeartRate != null) {
                var hr = info.currentHeartRate as Number;
                if (hr > HR_MIN && hr < 200) { return hr; }
            }
        } catch (e2) {
        }
        // 4. Sensor history - the last resort, and the one that needs the age
        // check most. These samples are the watch's all-day heart-rate log; they
        // persist after the watch is taken off, so an unchecked read here reports
        // a stale-but-believable figure forever. Only accept a sample recent
        // enough to be evidence the watch is on a wrist right now.
        try {
            if (SensorHistory has :getHeartRateHistory) {
                var iter = SensorHistory.getHeartRateHistory({:period => 1});
                if (iter != null) {
                    var s = iter.next();
                    if (s != null && s.data != null && s has :when && s.when != null) {
                        var age = nowSecs - (s.when as Time.Moment).value();
                        var hv = s.data as Number;
                        if (age >= 0 && age <= HR_HISTORY_MAX_AGE_SECS
                                && hv > HR_MIN && hv < 200) {
                            return hv;
                        }
                    }
                }
            }
        } catch (e3) {
        }
        return null;
    }

    // ── Bedtime probe ────────────────────────────────────────────────────────
    //
    // A short heart-rate check when Active Alarm Mode opens, purely so the sensor
    // can be verified AT BEDTIME.
    //
    // Sampling proper doesn't begin until roughly 105 minutes before the alarm,
    // which for a 06:00 alarm is 04:15 - so the status readout, whose whole
    // purpose is to prove the sensor works, only appeared while the user was
    // asleep. A reading taken now costs a few seconds of sensor time and answers
    // the only question that matters before going to bed.
    private static var _probeHr as Number = 0;
    private static var _probeDone as Boolean = false;
    private static var _probeAt as Number = 0;    // when the reading was taken
    private static var _probeSamples as Array<Number> = [];   // awaiting agreement
    private static var _probeSampleAt as Number = 0;          // when the last one arrived

    // Take one reading, and report a figure ONLY once several agree.
    //
    // A number existing is not the same as a number being right. The optical
    // sensor keeps producing output for a few seconds after the watch leaves your
    // wrist, while its algorithm loses lock, and those values look perfectly
    // ordinary. Requiring PROBE_MIN_AGREE readings within PROBE_AGREE_BAND beats
    // of each other is trivial to satisfy against a real pulse and awkward to
    // satisfy against noise, so the screen keeps saying "Checking HR..." instead
    // of announcing a figure it cannot stand behind.
    static function probe() as Void {
        startSensor();
        var hr = currentHr();
        var now = AlarmClock.now().value();
        if (hr == null) {
            _probeSamples = [];      // a gap breaks the run; start again
            return;
        }
        // A run only corroborates if its readings were taken close together. The
        // array being consecutive is not enough - leaving the screen and coming
        // back much later would otherwise let a twenty-minute-old reading vouch
        // for a fresh one. A negative gap (clock moved back) is equally unusable.
        var sinceLast = now - _probeSampleAt;
        if (_probeSampleAt > 0 && (sinceLast < 0 || sinceLast > PROBE_RUN_GAP_SECS)) {
            _probeSamples = [];
        }
        _probeSampleAt = now;
        _probeSamples.add(hr);
        var n = _probeSamples.size();
        if (n > PROBE_MIN_AGREE) {
            _probeSamples = _probeSamples.slice(n - PROBE_MIN_AGREE, null);
            n = PROBE_MIN_AGREE;
        }
        if (n < PROBE_MIN_AGREE) { return; }        // not corroborated yet

        var lo = _probeSamples[0];
        var hi = _probeSamples[0];
        var sum = 0;
        for (var i = 0; i < n; i++) {
            var v = _probeSamples[i];
            if (v < lo) { lo = v; }
            if (v > hi) { hi = v; }
            sum += v;
        }
        if ((hi - lo) > PROBE_AGREE_BAND) { return; }   // they disagree - keep looking

        _probeHr = sum / n;                              // agreed: report the mean
        _probeDone = true;
        _probeAt = now;
    }

    // Has the last check gone out of date?
    //
    // currentHr() rejects stale SOURCES, but the probe result is a snapshot taken
    // when the reading was still fresh, and a snapshot with no expiry is the same
    // mistake one level up: take the watch off and the screen kept showing the
    // last good figure indefinitely, because nothing ever asked again.
    //
    // This applies to BOTH outcomes. Expiring only successes made the behaviour
    // asymmetric: "HR: 63 BPM" would correct itself when the watch came off, but
    // "No HR Signal" was permanent, so putting the watch back on left the screen
    // insisting there was no signal until a button was pressed. A conclusion of
    // "no reading" is just as much a snapshot of a moment as a number is.
    static function probeExpired(nowSecs as Number) as Boolean {
        if (!_probeDone) { return false; }
        var age = nowSecs - _probeAt;
        if (age < 0) { return true; }   // clock moved back - re-check rather than trust it
        return age > PROBE_RESULT_TTL_SECS;
    }
    static function endProbe() as Void {
        _probeDone = true;
        // Stamp the CONCLUSION, whatever it was. Without this a failed check has
        // _probeAt == 0, which reads as infinitely old and would re-probe on every
        // single tick.
        _probeAt = AlarmClock.now().value();
        stopSensor();
    }
    static function probeHr() as Number { return _probeHr; }
    static function probeDone() as Boolean { return _probeDone; }

    // Start a completely fresh check.
    //
    // The RUN OF SAMPLES has to go too, not just the reported figure. Every
    // caller of this means "forget what you knew and measure again", and a
    // corroborating sample taken before that moment is exactly what we have
    // decided to stop trusting.
    //
    // Keeping the run reopened the bug it was built to close. Readings agree if
    // they arrived within PROBE_RUN_GAP_SECS of each other (60 s), so: wear the
    // watch, get "HR: 64 BPM", take the watch off, press a button 30 seconds
    // later. The reset cleared the 64 from the screen but left [64, 64, 64] in
    // the run, so ONE off-wrist reading of 68 was enough to fill the quorum -
    // and two on-wrist samples from before the watch came off voted it through.
    // The screen then showed a confident figure for a bare wrist, which is the
    // exact complaint corroboration exists to prevent.
    //
    // A new check now starts from zero and needs PROBE_MIN_AGREE readings taken
    // AFTER the reset, so nothing measured on a wrist can vouch for a reading
    // taken off one.
    static function resetProbe() as Void {
        _probeHr = 0;
        _probeDone = false;
        _probeSamples = [];
        _probeSampleAt = 0;
    }

    // ── Diagnostics ──────────────────────────────────────────────────────────
    // Surfaced on the Active Alarm screen. The whole reason this bug survived so
    // long is that a dead sensor looked identical to a normal night.
    static function sampleCount() as Number { return _samples.size(); }
    static function lastHr() as Number {
        var n = _samples.size();
        return (n > 0 && fresh()) ? _samples[n - 1] : 0;
    }
    static function ready() as Boolean { return fresh() && _samples.size() >= MIN_HR_SAMPLES; }

    // Optional secondary signal: Garmin's stress value (derived from HRV).
    // Higher stress generally tracks lighter sleep. Returns 0..100 or -1.
    static function stressLevel() as Number {
        try {
            if (SensorHistory has :getStressHistory) {
                var iter = SensorHistory.getStressHistory({:period => 1});
                if (iter != null) {
                    var s = iter.next();
                    if (s != null && s.data != null && s.when != null) {
                        var age = AlarmClock.now().value() - s.when.value();
                        var value = s.data as Number;
                        if (age >= 0 && age <= HR_HISTORY_MAX_AGE_SECS && value >= 0) {
                            return clamp(value, 0, 100);
                        }
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
        if (!fresh() || n < MIN_HR_SAMPLES) { return -1; }
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

        // Variability: recent sample-to-sample change vs the night's typical change.
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
        // A peak from much earlier in the window cannot justify waking during
        // deep sleep now. Expire it after three minutes of sensor samples.
        if (s >= _best || _seq - _bestSeq > RECENT_SAMPLES) {
            _best = s;
            _bestSeq = _seq;
        }

        // Require a recent peak and decline. The threshold decreases toward
        // the deadline, while the current score must remain at least LATE_BAR.
        if (progress >= PEAK_MIN_PROGRESS) {
            var bar = PEAK_BAR + (PEAK_BAR_EARLY - PEAK_BAR) * (1.0 - progress);
            if (_best >= bar && s >= LATE_BAR && s <= _best - PEAK_DROP) { return true; }
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
        _lightCacheN = -1;
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
    // with one bounded temporary array per call.
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

    // Awake evidence uses sustained elevation relative to the session floor.
    // These thresholds are heuristics, not measured sleep-stage accuracy.
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
        var walkAge = AlarmClock.now().value() - _walkAt;
        if (_walkAt > 0 && walkAge >= 0 && walkAge <= WALK_WINDOW_SECS) { return true; }
        if (!fresh()) { return false; }
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
