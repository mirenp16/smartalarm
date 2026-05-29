// SmartAlarmApp.mc
// Entry point for the app. Registers the background service on start.

import Toybox.Application;
import Toybox.Background;
import Toybox.System;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

class SmartAlarmApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        // Register background service if alarm is enabled.
        // The background service handles re-registration automatically.
        if (AlarmStorage.isAlarmEnabled()) {
            SmartAlarmApp.registerBackground();
        }
    }

    function onStop(state as Dictionary?) as Void {
        // Nothing to clean up — background keeps running even when app closes.
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new MainView(), new MainDelegate()];
    }

    // Returns the background service delegate — this is how the compiler
    // discovers SleepMonitorDelegate and resolves Background.ServiceDelegate.
    // The (:background) annotation includes this method in the background build.
    (:background)
    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new SleepMonitorDelegate()];
    }

    // Called when the background service sends data back to the foreground.
    function onBackgroundData(data) as Void {
        WatchUi.requestUpdate();
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    static function registerBackground() as Void {
        if (Toybox.Background has :registerForTemporalEvent) {
            Background.registerForTemporalEvent(
                new Time.Duration(CHECK_INTERVAL_SECS)
            );
        }
    }

    static function unregisterBackground() as Void {
        if (Toybox.Background has :deleteTemporalEvent) {
            Background.deleteTemporalEvent();
        }
    }
}

function getApp() as SmartAlarmApp {
    return Application.getApp() as SmartAlarmApp;
}