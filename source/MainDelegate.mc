// MainDelegate.mc
// Handles button presses on the main screen.
//
// SELECT → opens the settings menu
// BACK   → exits the app (Garmin handles this automatically, but we confirm)

import Toybox.Lang;
import Toybox.WatchUi;

class MainDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    // SELECT button pressed
    function onSelect() as Boolean {
        WatchUi.pushView(
            new SettingsMenu(),
            new SettingsMenuDelegate(),
            WatchUi.SLIDE_UP
        );
        return true;
    }

    // BACK / LAP button — let Garmin's default behaviour close the app
    function onBack() as Boolean {
        return false;  // false = let the system handle it (exits the app)
    }

    // Menu button (older devices) — same as SELECT
    function onMenu() as Boolean {
        return onSelect();
    }
}