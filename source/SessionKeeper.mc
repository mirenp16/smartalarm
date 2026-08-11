// SessionKeeper.mc
// Keeps Active Alarm Mode pinned in the foreground.
//
// THE PROBLEM: covering the watch with your palm is handled by Garmin's OS
// before any app sees it - it turns off the display and returns to the watch
// face, killing Active Alarm Mode and the alarm with it. No Connect IQ API can
// intercept that gesture.
//
// THE WORKAROUND: Garmin keeps an app in the foreground for as long as it has an
// ActivityRecording session running, and won't let the watch drop out of the app
// while one is active. So Active Alarm Mode starts a session purely as an anchor.
//
// It is NEVER saved - discard() is always used, so nothing appears in Garmin
// Connect and no bogus workout is uploaded. GPS is never requested.
//
// Everything is guarded: if recording is unavailable the alarm still works
// exactly as before, just without the palm protection.

import Toybox.ActivityRecording;
import Toybox.Lang;

class SessionKeeper {

    private static var _session = null;

    // Starts the anchor session. Safe to call repeatedly.
    static function start() as Boolean {
        if (_session != null) { return true; }
        try {
            if (!(Toybox has :ActivityRecording)) { return false; }
            _session = ActivityRecording.createSession({
                :name  => "Smart Alarm",
                :sport => ActivityRecording.SPORT_GENERIC
            });
            if (_session != null) {
                _session.start();
                return true;
            }
        } catch (e) {
            _session = null;
        }
        return false;
    }

    // Ends the session and throws it away - never saved.
    static function stop() as Void {
        if (_session == null) { return; }
        try {
            if (_session.isRecording()) { _session.stop(); }
            _session.discard();
        } catch (e) {
        }
        _session = null;
    }

    static function isActive() as Boolean { return _session != null; }
}
