// BedsideView.mc  ("Active Alarm Mode")
// The only place alarms ring. Runs in the foreground so it can vibrate/beep and
// open the ringing screen directly - a Connect IQ background service can do
// neither. You enter it at bedtime; enabled alarms fire while it's up.
//
// Battery-minimal: near-black screen, a tick that slows to 60 s when no alarm is
// near, and heart-rate sampling only once a Sleep Cycle Window is approaching.
//
// When idle the screen shows ONLY the title, current time and next alarm (dim, so
// it barely lights the AMOLED). Pressing any button reveals the exit controls for
// a few seconds. Exit is deliberately a two-step combo: BACK, then UP.

import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

class BedsideView extends WatchUi.View {

    private var _timer as Timer.Timer?;
    private var _ringingShown as Boolean = false;
    private var _exitArmed as Boolean = false;
    private var _armSecs as Number = 0;
    private var _controlsSecs as Number = -100;    // when controls were last revealed
    private var _lastDrawMin as Number = -1;       // throttles redraws to once a minute
    private var _tickMs as Number = 0;             // current timer cadence
    private var _nextStr as String? = null;        // cached "Next Alarm" text
    private var _durStr as String? = null;         // cached "Duration:" text
    private var _sampling as Boolean = false;      // is the HR session open?
    private var _probeTicks as Number = 0;         // bedtime sensor-check ticks used
    private var _w as Number = 360;
    private var _h as Number = 360;
    private var _cx as Number = 180;
    private var _cy as Number = 180;

    function initialize() { View.initialize(); }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();  _h = dc.getHeight();
        _cx = _w / 2;        _cy = _h / 2;
    }

    // Set by the ringing screen once an alarm has been dismissed and there is
    // nothing left to wait for - we then close Active Alarm Mode automatically
    // instead of making the user enter the passcode a second time.
    public static var exitRequested as Boolean = false;

    function onShow() as Void {
        if (exitRequested) {
            exitRequested = false;
            stopTimer();
            MainListMenu.show(WatchUi.SLIDE_DOWN);
            return;
        }

        // NOTE: an ActivityRecording session was tried here to pin the app in the
        // foreground against the palm gesture. It worked, but the watch logged the
        // whole night as an activity (destroying sleep tracking) and cost ~24%
        // battery, so it was removed. The palm gesture remains unavoidable; the
        // practical defence is turning the touchscreen off overnight.
        if (AlarmStore.ringingId() == null) { _ringingShown = false; }

        // Drop every cached display string on the way back in.
        //
        // Alarm state can change while this view is hidden - snoozing is the
        // obvious case, and it moves the next fire time. The cached "Next Alarm"
        // and "Duration" strings were computed before that happened, and the tick
        // only recomputes them when the displayed MINUTE changes. Snooze at 12:00
        // and return within the same minute, and the screen kept showing the
        // pre-snooze values until 12:01. Clearing here forces the next draw to
        // recompute, which costs one alarm scan on a screen transition.
        _nextStr = null;
        _durStr = null;
        _lastDrawMin = -1;
        // Re-check the sensor each time Active Alarm Mode is opened, so the
        // status line reflects tonight rather than a previous session. Probe
        // straight away rather than waiting for the first tick, which on the slow
        // cadence would leave "checking HR..." on screen for a whole minute.
        if (_probeTicks == 0) {
            SleepDetector.resetProbe();
            try {
                // Already inside the sampling window? Then start real sampling
                // straight away, so the first frame shows the live readout rather
                // than a probe result that is about to be replaced.
                if (AlarmEngine.shouldSampleAt(AlarmEngine.secsUntilNextTarget(Time.now().value()))) {
                    SleepDetector.startSensor();
                    SleepDetector.sample();
                    _sampling = true;
                    _probeTicks = PROBE_TICKS;
                } else {
                    // Start the check now rather than waiting for the first tick.
                    //
                    // It cannot CONCLUDE here: a figure is only reported once
                    // PROBE_MIN_AGREE readings agree, and this is the first, so
                    // the run always continues on the tick loop. The early-release
                    // branch that used to live here became unreachable the moment
                    // corroboration was introduced, and was removed rather than
                    // left to misdescribe the code.
                    SleepDetector.probe();
                    _probeTicks = 1;
                }
            } catch (ep) {
                _probeTicks = 1;
            }
        }
        startTimer(intervalFor(AlarmEngine.secsUntilNextTarget(Time.now().value())));
    }

    // 5 s while the bedtime heart-rate check is running, 15 s near an alarm,
    // 60 s the rest of the night (4x fewer CPU wakeups).
    //
    // ONE function decides this, and both callers use it. There used to be two
    // copies of the rule - onShow() had its own, which knew nothing about the
    // heart-rate probe. Opening Active Alarm Mode hours before an alarm therefore
    // armed a 60-second timer, so when the first probe found nothing the retry sat
    // a full minute away and "Checking HR..." stayed on screen the whole time.
    //
    // Takes the distance as an argument so the caller that already computed it
    // doesn't pay for a second alarm scan.
    private function intervalFor(secsUntil as Number) as Number {
        if (_probeTicks < PROBE_TICKS) { return PROBE_TICK_MS; }
        if (secsUntil >= 0 && secsUntil <= FAST_TICK_WITHIN_SECS) { return TICK_FAST_MS; }
        return TICK_SLOW_MS;
    }

    private function startTimer(ms as Number) as Void {
        if (_timer != null && _tickMs == ms) { return; }   // already correct
        stopTimer();
        _tickMs = ms;
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), ms, true);
    }

    // Leaving the view releases the sensor. Without this an open HR session
    // would keep draining the battery after Active Alarm Mode had gone away.
    //
    // Released UNCONDITIONALLY, not just when _sampling is set. The bedtime probe
    // also opens a session, and when it finds no heart rate (watch off the wrist)
    // it stays open waiting for one while _sampling is still false. Guarding on
    // _sampling therefore leaked the sensor for as long as the app stayed
    // running. stopSensor() is a no-op when no session is open, so calling it
    // every time is both safe and correct.
    function onHide() as Void {
        stopTimer();
        try { SleepDetector.stopSensor(); } catch (e) { }
        _sampling = false;
    }

    // The whole body is guarded. This runs unattended for hours, and a single
    // uncaught exception used to kill the app (the "IQ!" screen) and take the
    // alarm with it. Sleep sampling is best-effort; the alarm itself must survive.
    function onTick() as Void {
        var now = Time.now().value();
        // Negative age = the clock moved back; the arm stamp is meaningless, so
        // lapse it rather than leave the exit gesture armed indefinitely.
        var armAge = now - _armSecs;
        if (_exitArmed && (armAge < 0 || armAge > EXIT_ARM_SECS)) { _exitArmed = false; }

        // Roll the daily state over BEFORE anything reads a fired flag.
        //
        // evaluate() does this too, but it runs later in the tick - and
        // secsUntilNextTarget() below asks whether each alarm has already fired
        // TODAY. Just after midnight, with the rollover still pending, "today"
        // still meant yesterday, so every alarm that rang yesterday looked spent
        // and resolved to its NEXT day instead of this one. A 00:30 daily alarm
        // reported 24.5 hours away rather than 30 minutes, which showed a wrong
        // Duration on screen and, worse, told shouldSampleAt() there was nothing
        // to warm up for - costing a tick of heart-rate lead at the one moment it
        // is being collected. It corrected itself on the following tick, up to a
        // minute later on the idle cadence.
        //
        // Ordering it first is free: the check memoises the day it last
        // confirmed, so evaluate()'s own call is now a compare.
        try {
            AlarmStore.resetIfNewDay();
        } catch (eD) {
        }

        // Work out the distance to the next alarm ONCE and reuse it. This scan
        // walks every alarm, so doing it repeatedly per tick was a large part of
        // the load that tripped the watchdog.
        var secsUntil = -1;
        try {
            secsUntil = AlarmEngine.secsUntilNextTarget(now);
        } catch (e0) {
        }

        try {
            // Only read the heart-rate sensor when a wake window is approaching.
            // For most of the night there is nothing to detect, so staying idle
            // here saves a large amount of battery.
            //
            // The sensor SESSION is opened and closed alongside the sampling
            // window. Previously no session was ever opened at all, which is why
            // no heart-rate data ever reached the detector.
            if (AlarmEngine.shouldSampleAt(secsUntil)) {
                SleepDetector.startSensor();
                SleepDetector.sample();
                _sampling = true;
                _probeTicks = PROBE_TICKS;      // probe is moot once really sampling
            } else if (_sampling) {
                SleepDetector.stopSensor();
                _sampling = false;
                // Re-arm the bedtime check on the way back to idle.
                //
                // Entering Active Alarm Mode already inside the sampling window
                // skips the probe entirely (_probeTicks is set to PROBE_TICKS but
                // probeDone is never set). If sampling then stopped - a backup
                // alarm just over the sampling horizon, say - the status line had
                // no completed probe to report and no way left to run one, so it
                // sat on "Checking HR..." indefinitely. Re-arming both restores a
                // meaningful readout and re-confirms the sensor.
                _probeTicks = 0;
                SleepDetector.resetProbe();
            } else if (SleepDetector.probeExpired(now)) {
                // The displayed reading has gone out of date - take it again
                // rather than leave a stale figure on screen.
                _probeTicks = 0;
                SleepDetector.resetProbe();
                _lastDrawMin = -1;
            } else if (_probeTicks < PROBE_TICKS) {
                // Bedtime check: give the sensor a few ticks to produce a reading
                // so the status line can be trusted before going to sleep, then
                // release it again for the rest of the night.
                SleepDetector.probe();
                _probeTicks++;
                if (_probeTicks >= PROBE_TICKS || SleepDetector.probeHr() > 0) {
                    _probeTicks = PROBE_TICKS;
                    SleepDetector.endProbe();
                }
                _lastDrawMin = -1;              // show the result immediately
            }
        } catch (e) {
            // Sensor hiccup - keep going, the deadline will still fire.
        }

        try {
            if (AlarmStore.ringingId() != null) { showRinging(); return; }

            var id = AlarmEngine.evaluate(now);
            if (id >= 0) {
                AlarmStore.beginRing(id);
                showRinging();
                return;
            }
        } catch (e2) {
            // Never let a scheduling error stop the clock.
        }

        // Speed up as the alarm approaches, slow down again afterwards. Reuses
        // the distance computed above rather than scanning the alarms again.
        startTimer(intervalFor(secsUntil));

        // Redraw when the displayed minute changes - redrawing every 15 s all
        // night is wasted work, since nothing on screen moves.
        //
        // EXCEPT while sampling, when the heart-rate figure changes every tick and
        // a once-a-minute refresh makes the readout look frozen. That only applies
        // inside the ~105-minute sampling window, and the CPU is already awake for
        // the tick, so the extra cost is a few hundred text draws across a night.
        var mins = now / 60;
        if (_sampling) { _lastDrawMin = -1; }
        if (mins != _lastDrawMin) {
            _lastDrawMin = mins;
            _nextStr = computeNextAlarmStr();   // done here, not while drawing
            _durStr  = computeDurationStr();
            WatchUi.requestUpdate();
        }
    }

    private function showRinging() as Void {
        if (!_ringingShown) {
            _ringingShown = true;
            var rv = new RingingView();
            WatchUi.pushView(rv, new RingingDelegate(rv), WatchUi.SLIDE_UP);
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var vc = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);

        // Title, curved along the top of the bezel (falls back to straight text).
        Ui.labelSized(dc, _w, _h, 90, UI_TITLE, "Active Alarm Mode", 28);

        // Current time
        // LAYOUT. Everything sits higher than it used to, closing the gap under
        // the title, to free a row beneath the heart-rate line for the countdown.
        // The y positions are chosen so no two elements' half-heights overlap and
        // every string fits the CHORD width at its own height - a round screen is
        // only 307 px wide at 76% down, not 360.
        dc.setColor(UI_LABEL, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 80, Graphics.FONT_XTINY, "Current Time", vc);
        dc.setColor(UI_VALUE, Graphics.COLOR_TRANSPARENT);
        // 34 px between caption and value, matching the "Next Alarm" pair below.
        // At 28 px the FONT_MEDIUM ascenders came close enough to the caption to
        // read as touching.
        dc.drawText(_cx, _cy - 46, Graphics.FONT_MEDIUM, Fmt.time12(now.hour, now.min), vc);

        // Next alarm (shows the snooze time if an alarm is snoozed)
        dc.setColor(UI_LABEL, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy - 8, Graphics.FONT_XTINY, "Next Alarm", vc);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + 26, Graphics.FONT_LARGE, nextAlarmStr(), vc);

        // Heart-rate status. ALWAYS shown, in one of three states.
        //
        // This exists because the smart-wake failure was INVISIBLE: with no HR
        // data the app quietly behaved like an ordinary alarm and there was no
        // way to tell from the watch that anything was wrong.
        //
        // It originally appeared only once sampling had begun - about 105 minutes
        // before the alarm. For a 06:00 alarm that is 04:15, so the one indicator
        // meant to reassure you at bedtime was only visible while you were
        // asleep. Hence the bedtime probe: a reading is taken as soon as this
        // screen opens, and the line reports something useful at every hour.
        // Kept SHORT. An earlier version read "HR 63  tracks from 12:44 AM",
        // which overran the usable width of a round screen at this height (the
        // chord is only ~307 px at 76% down, not the full 360) and still left the
        // reader wondering what it meant. Every state now fits in about half the
        // width and says one thing.
        var hrTxt;
        var hrCol;
        if (_sampling) {
            var hr = SleepDetector.lastHr();
            var cnt = SleepDetector.sampleCount();
            if (cnt == 0 || hr == 0) {
                hrTxt = "No HR Signal";
                hrCol = UI_AMBER;
            } else if (!SleepDetector.ready()) {
                hrTxt = "HR: " + hr.format("%d") + " BPM  " + cnt.format("%d")
                        + "/" + MIN_HR_SAMPLES.format("%d");
                hrCol = UI_HR;
            } else {
                hrTxt = "HR: " + hr.format("%d") + " BPM  ready";
                hrCol = UI_HR;
            }
        } else if (!SleepDetector.probeDone()) {
            hrTxt = "Checking HR...";
            hrCol = UI_DIM;
        } else if (SleepDetector.probeHr() > 0) {
            hrTxt = "HR: " + SleepDetector.probeHr().format("%d") + " BPM";
            hrCol = UI_HR;
        } else {
            hrTxt = "No HR Signal";
            hrCol = UI_AMBER;
        }
        dc.setColor(hrCol, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + 66, Graphics.FONT_XTINY, hrTxt, vc);

        // How long until the alarm actually goes off. Uses the same source as the
        // scheduler, so a snooze shortens it automatically and "NONE" reads
        // "--:--" rather than a misleading zero.
        dc.setColor(UI_LABEL, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + 94, Graphics.FONT_XTINY, durationStr(), vc);

        // Exit controls only appear briefly after a button press.
        if (controlsVisible()) {
            dc.setColor(_exitArmed ? UI_BLUE : UI_LABEL, Graphics.COLOR_TRANSPARENT);
            var hint = _exitArmed ? "Press UP now to exit" : "BACK then UP to exit";
            dc.drawText(_cx, _h * 84 / 100, Graphics.FONT_XTINY, hint, vc);
            Ui.back(dc, _w, _h, "BACK");
            Ui.up(dc, _w, _h, "UP");
        }
    }


    // "Duration: HH:MM" until the next alarm actually rings.
    //
    // secsUntilNextTarget() already folds in a pending snooze and skips alarms
    // that have fired, so this needs no separate snooze handling: snoozing simply
    // makes the number smaller.
    function durationStr() as String {
        if (_durStr == null) { _durStr = computeDurationStr(); }
        return _durStr as String;
    }

    private function computeDurationStr() as String {
        var d = -1;
        try {
            d = AlarmEngine.secsUntilNextTarget(Time.now().value());
        } catch (e) {
        }
        return "Duration: " + Fmt.duration(d);
    }

    // Cached string, refreshed on tick. Drawing must stay cheap: computing this
    // inside onUpdate() meant a full alarm scan on every redraw.
    function nextAlarmStr() as String {
        if (_nextStr == null) { _nextStr = computeNextAlarmStr(); }
        return _nextStr as String;
    }

    private function computeNextAlarmStr() as String {
        var nowSecs = Time.now().value();
        // Only show a snooze time if that alarm still exists (validSnoozeId
        // clears the snooze when its alarm has been deleted).
        if (AlarmStore.validSnoozeId() != null) {
            var snU = AlarmStore.snoozeUntil();
            if (snU != null && snU > nowSecs) {
                var si = Gregorian.info(new Time.Moment(snU), Time.FORMAT_SHORT);
                return Fmt.time12(si.hour, si.min);
            }
        }
        var next = AlarmEngine.nextAlarm(nowSecs);
        return (next != null) ? Fmt.time12(AlarmStore.hour(next), AlarmStore.minute(next)) : "NONE";
    }

    // ── Controls / exit ──────────────────────────────────────────────────────

    function revealControls() as Void {
        _controlsSecs = Time.now().value();
        // A button press also asks for a FRESH heart-rate reading. Keeping the
        // sensor on continuously is what costs real battery (an always-on session
        // measured ~24% a night); a probe on demand costs at most PROBE_TICKS
        // ticks of sensor time and only when you actually look at the watch.
        if (!_sampling) {
            _probeTicks = 0;
            SleepDetector.resetProbe();
            // The TIMER has to be re-armed too, not just the probe counter.
            // onShow() and onTick() both call startTimer() after touching
            // _probeTicks; this path did not, so the fresh reading waited for the
            // next scheduled tick - up to a full minute on the idle cadence, which
            // defeats the point of asking for it. _probeTicks is 0 here, so
            // intervalFor() returns the probe cadence whatever the alarm distance.
            startTimer(intervalFor(-1));
        }
        WatchUi.requestUpdate();
    }
    function controlsVisible() as Boolean {
        var age = Time.now().value() - _controlsSecs;
        return age >= 0 && age <= 6;
    }

    // BACK arms the exit. It must be followed IMMEDIATELY by UP - any other
    // button in between calls disarm() and the sequence starts over.
    function armExit() as Void {
        _exitArmed = true;
        _armSecs = Time.now().value();
        revealControls();
    }
    function disarmExit() as Void {
        _exitArmed = false;
        revealControls();
    }
    function exitReady() as Boolean {
        if (!_exitArmed) { return false; }
        var age = Time.now().value() - _armSecs;
        return age >= 0 && age <= EXIT_ARM_SECS;
    }

    function stopTimer() as Void {
        if (_timer != null) { _timer.stop(); _timer = null; }
    }
}

class BedsideDelegate extends WatchUi.BehaviorDelegate {

    private var _view as BedsideView;

    function initialize(view as BedsideView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // BACK reveals controls and arms the exit.
    function onBack() as Boolean { _view.armExit(); return true; }

    // UP completes the exit ONLY if BACK was the button pressed immediately
    // before it. Otherwise it just reveals the controls (and stays disarmed).
    function onPreviousPage() as Boolean {
        if (_view.exitReady()) {
            _leave();
        } else {
            _view.disarmExit();
        }
        return true;
    }

    // Any other button breaks the BACK->UP sequence.
    function onSelect() as Boolean { _view.disarmExit(); return true; }
    function onNextPage() as Boolean { _view.disarmExit(); return true; }

    // ── Touchscreen fully disabled ───────────────────────────────────────────
    // Every touch gesture is swallowed (returning true stops it being handled),
    // so a stray touch or swipe in your sleep can't disturb Active Alarm Mode.
    function onTap(evt as WatchUi.ClickEvent) as Boolean { return true; }
    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean { return true; }
    function onHold(evt as WatchUi.ClickEvent) as Boolean { return true; }
    function onDrag(evt) as Boolean { return true; }
    function onRelease(evt as WatchUi.ClickEvent) as Boolean { return true; }
    function onFlick(evt) as Boolean { return true; }

    // Leaving Active Alarm Mode. Whether a passcode is needed is decided by the
    // NEXT upcoming alarm - if its Passcode toggle is off, BACK->UP just exits.
    // With no upcoming alarm at all, no code is needed either.
    private function _leave() as Void {
        // governingAlarm counts a snoozed/ringing alarm too, so hitting snooze
        // can't be used to slip out without the passcode.
        var next = AlarmEngine.governingAlarm(Time.now().value());
        if (next != null && AlarmStore.passcodeOn(next)) {
            var pv = new PasscodeView(PC_MODE_ENTER, method(:finishLeave));
            WatchUi.pushView(pv, new PasscodeDelegate(pv), WatchUi.SLIDE_UP);
            return;
        }
        finishLeave();
    }

    // Runs AFTER the passcode screen has closed, so switchToView replaces the
    // Active Alarm view (not the passcode view) and the exit actually sticks.
    function finishLeave() as Void {
        _view.stopTimer();
        MainListMenu.show(WatchUi.SLIDE_DOWN);
    }
}
