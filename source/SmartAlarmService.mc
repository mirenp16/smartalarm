// SmartAlarmService.mc
// The background service. The OS wakes this every ~5 minutes even while the app
// is closed. It uses the shared AlarmEngine to decide if an alarm should fire.
//
// IMPORTANT platform limit: a background process on Garmin cannot vibrate, beep,
// or open the app. Its ONLY option is Background.requestApplicationWake(), which
// shows a system "open the app?" prompt and waits for the user to look. For
// reliable, on-time, prompt-free waking, use Bedside Mode (a foreground screen).
//
// In SDK 9 ServiceDelegate lives in Toybox.System (not Toybox.Background).

import Toybox.Background;
import Toybox.System;
import Toybox.Application;
import Toybox.Lang;
import Toybox.Time;

(:background)
class SmartAlarmService extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        // Already ringing but not yet handled? Keep nudging.
        if (AlarmStore.ringingId() != null) {
            requestWake("Smart Alarm");
            Background.exit(null);
            return;
        }

        var id = AlarmEngine.evaluate(Time.now().value());
        if (id >= 0) {
            AlarmStore.beginRing(id);
            var found = AlarmStore.findById(id);
            var msg = (found[1] != null) ? AlarmStore.label(found[1] as Dictionary) : "Alarm";
            requestWake(msg);
        }

        Background.exit(null);
    }

    // Shows the system prompt asking to open the app. Wrapped in try/catch so an
    // unsupported device can never crash the service.
    private function requestWake(msg as String) as Void {
        try {
            Background.requestApplicationWake(msg);
        } catch (e) {
        }
    }
}
