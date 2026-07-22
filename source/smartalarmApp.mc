// SmartAlarmApp.mc
// Application entry point. Decides whether to open the normal alarm list or jump
// straight to the ringing screen, wires up the background service, and keeps the
// repeating temporal event registered whenever at least one alarm is enabled.

import Toybox.Application;
import Toybox.Background;
import Toybox.System;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// NOTE: the class itself is NOT annotated (:background). Only getServiceDelegate()
// below is, so the background build pulls in the service (and what it needs)
// without dragging the foreground UI classes into the tiny background context.
class SmartAlarmApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        syncBackground();
    }

    function onStop(state as Dictionary?) as Void {
    }

    // If an alarm is currently ringing (flagged by the background service), open
    // straight into the ringing screen. Otherwise show the alarm list.
    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        if (AlarmStore.ringingId() != null) {
            var rv = new RingingView();
            return [rv, new RingingDelegate(rv)];
        }
        var lv = new AlarmListView();
        return [lv, new AlarmListDelegate(lv)];
    }

    // The background service that runs while the app is closed.
    (:background)
    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new SmartAlarmService()];
    }

    // Called when the background service surfaces the app. If an alarm is ringing,
    // push the ringing screen on top of whatever is showing.
    function onBackgroundData(data) as Void {
        if (AlarmStore.ringingId() != null) {
            var rv = new RingingView();
            WatchUi.pushView(rv, new RingingDelegate(rv), WatchUi.SLIDE_UP);
        }
        WatchUi.requestUpdate();
    }

    // ── Background registration helpers ──────────────────────────────────────

    // Registers the repeating 5-minute temporal event if any alarm is enabled;
    // otherwise cancels it to save battery.
    static function syncBackground() as Void {
        if (anyAlarmEnabled()) {
            registerBackground();
        } else {
            unregisterBackground();
        }
    }

    static function registerBackground() as Void {
        try {
            Background.registerForTemporalEvent(new Time.Duration(CHECK_INTERVAL_SECS));
        } catch (e) {
        }
    }

    static function unregisterBackground() as Void {
        try {
            Background.deleteTemporalEvent();
        } catch (e) {
        }
    }

    static function anyAlarmEnabled() as Boolean {
        var list = AlarmStore.getAlarms();
        for (var i = 0; i < list.size(); i++) {
            if (AlarmStore.isOn(list[i] as Dictionary)) { return true; }
        }
        return false;
    }
}

function getApp() as SmartAlarmApp {
    return Application.getApp() as SmartAlarmApp;
}
