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
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var menu = new MainListMenu();
        return [menu, new MainListDelegate(menu)];
    }
}

function getApp() as SmartAlarmApp {
    return Application.getApp() as SmartAlarmApp;
}
