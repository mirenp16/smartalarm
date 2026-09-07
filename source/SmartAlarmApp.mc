// SmartAlarmApp.mc
// Application entry point. There is no background service: alarms only ring while
// you are inside Active Alarm Mode (a foreground screen you enter at bedtime).
// The home screen is the native-style alarm list.

import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class SmartAlarmApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        // Start from persistent storage rather than any stale in-memory cache.
        AlarmStore.invalidate();

        // Settle which day it is BEFORE anything reads or writes a per-day flag.
        //
        // The app may have been closed for days. clearStaleRing() below calls
        // markFired(), and without this that write landed in the day-state
        // dictionary belonging to whenever the app was last open - a flag for the
        // wrong day, wiped moments later by the first rollover. Nothing broke,
        // because the grace check retires an overdue alarm anyway, but it meant
        // one of the four entry points reasoned about "today" differently from
        // the other three. They now all settle the day first.
        AlarmStore.resetIfNewDay();

        // If the app was killed while an alarm was ringing, that "ringing" flag
        // survives in storage. Without this the app would open straight into the
        // ringing screen for an alarm that was due hours ago.
        AlarmStore.clearStaleRing();
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var menu = new MainListMenu();
        return [menu, new MainListDelegate()];
    }
}

// NOTE: the project template's global getApp() helper used to live here. Nothing
// in this app ever called it - every piece of shared state lives in AlarmStore
// as static members, reachable without a handle on the application object - so
// it was removed rather than left as scaffolding that implies a pattern the code
// does not actually use.
