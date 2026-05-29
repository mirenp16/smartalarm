// SleepMonitorDelegate.mc
// Background service — wakes up every 5 minutes to check sleep lightness.
//
// State machine (stored in persistent storage so it survives across wake-ups):
//   0 = idle          — outside monitoring window, do nothing
//   1 = monitoring    — inside window, sampling sleep data
//   2 = fired         — alarm already triggered today, wait for reset
//
// Monitoring window: [alarmTime - windowMinutes]  →  [alarmTime]
// Hard deadline: if we reach alarmTime without detecting light sleep,
//                fire the alarm anyway so the user is never late.

import Toybox.Background;
import Toybox.System;
import Toybox.Application;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Lightness threshold to fire early. 65/100 means "comfortably light sleep".
// Raise this to fire only when very close to awake; lower it to fire earlier.
const LIGHT_SLEEP_THRESHOLD = 65;

// Re-check interval in seconds (5 minutes = 300 s).
// Garmin's minimum background interval is 5 minutes.
const CHECK_INTERVAL_SECS = 300;

(:background)
class SleepMonitorDelegate extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    // Called by the OS every time a temporal event fires.
    function onTemporalEvent() as Void {

        // ── Guard: only run on configured alarm days ──────────────────────────
        if (!AlarmStorage.isAlarmEnabled() || !AlarmStorage.isAlarmDay()) {
            _scheduleNextCheck();
            Background.exit(null);
            return;
        }

        // ── Current time as minutes since midnight ────────────────────────────
        var nowInfo       = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var currentMins   = nowInfo.hour * 60 + nowInfo.min;
        var alarmMins     = AlarmStorage.getAlarmTotalMinutes();
        var windowStart   = alarmMins - AlarmStorage.getWindowMinutes();

        // ── Read persisted state ──────────────────────────────────────────────
        var state = Application.Storage.getValue("monitorState");
        if (state == null) { state = 0; }

        // ── Past alarm time: reset for tomorrow ───────────────────────────────
        if (currentMins > alarmMins + 10) {
            AlarmStorage.resetDailyState();
            _scheduleNextCheck();
            Background.exit(null);
            return;
        }

        // ── Alarm already fired today ─────────────────────────────────────────
        if (state == 2) {
            Background.exit(null);
            return;
        }

        // ── Hard deadline: fire now if we've hit alarm time ───────────────────
        if (currentMins >= alarmMins) {
            _fireAlarm();
            Application.Storage.setValue("monitorState", 2);
            Background.exit(null);
            return;
        }

        // ── Not yet in monitoring window ──────────────────────────────────────
        if (currentMins < windowStart) {
            _scheduleNextCheck();
            Background.exit(null);
            return;
        }

        // ── In monitoring window: evaluate sleep ──────────────────────────────
        Application.Storage.setValue("monitorState", 1);

        var score = SleepDetector.getLightnessScore();

        // Track the best (lightest) score seen during this window
        var bestScore = Application.Storage.getValue("bestScore");
        if (bestScore == null || score > bestScore) {
            Application.Storage.setValue("bestScore", score);
        }

        // Fire if we've crossed the light-sleep threshold
        if (score >= LIGHT_SLEEP_THRESHOLD) {
            _fireAlarm();
            Application.Storage.setValue("monitorState", 2);
        } else {
            // Not light enough yet — check again in 5 minutes
            _scheduleNextCheck();
        }

        Background.exit(null);
    }

    // ── Private ───────────────────────────────────────────────────────────────

    private function _fireAlarm() as Void {
        var mode = AlarmStorage.getAlarmMode();

        if (mode == MODE_VIBE_AND_SOUND || mode == MODE_VIBE_ONLY) {
            _vibrate();
        }
        if (mode == MODE_VIBE_AND_SOUND || mode == MODE_SOUND_ONLY) {
            _playTone();
        }

        // Record the time the alarm fired so MainView can display it
        Application.Storage.setValue("lastAlarmTime", Time.now().value());
    }

    private function _vibrate() as Void {
        if (!(Attention has :vibrate)) { return; }
        // Pattern: two short pulses then one long — feels distinct from
        // notification buzzes.
        Attention.vibrate([
            new Attention.VibeProfile(80, 300),
            new Attention.VibeProfile(0,  150),
            new Attention.VibeProfile(80, 300),
            new Attention.VibeProfile(0,  150),
            new Attention.VibeProfile(100, 700)
        ]);
    }

    private function _playTone() as Void {
        if (!(Attention has :playTone)) { return; }
        Attention.playTone(Attention.TONE_ALARM);
    }

    // Re-registers for the next 5-minute check.
    private function _scheduleNextCheck() as Void {
        if (Toybox.Background has :registerForTemporalEvent) {
            Background.registerForTemporalEvent(
                new Time.Duration(CHECK_INTERVAL_SECS)
            );
        }
    }
}