// MainView.mc
// The main screen. Drawn entirely with the DC (device context) for a clean,
// custom look on the Forerunner 265S AMOLED display (246 × 246 px, round).
//
// Layout (top → bottom):
//   "SMART ALARM" label
//   Coloured ring (green = enabled, grey = disabled)
//   Large alarm time  e.g.  7:30 AM
//   "Smart window: -45 min" subtitle
//   Day-of-week dots  S M T W T F S
//   Alert-mode icon   ♪+⚡  ♪  ⚡
//   Status text       ● Armed  /  ● Monitoring...  /  ○ Off
//   "SELECT to edit" hint

import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

class MainView extends WatchUi.View {

    // Cached screen geometry — set in onLayout
    private var _w  as Number = 246;
    private var _h  as Number = 246;
    private var _cx as Number = 123;
    private var _cy as Number = 123;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w  = dc.getWidth();
        _h  = dc.getHeight();
        _cx = _w / 2;
        _cy = _h / 2;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        // ── Background ────────────────────────────────────────────────────────
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var enabled  = AlarmStorage.isAlarmEnabled();
        var hour     = AlarmStorage.getAlarmHour();
        var minute   = AlarmStorage.getAlarmMinute();
        var mode     = AlarmStorage.getAlarmMode();
        var days     = AlarmStorage.getAlarmDays();
        var window   = AlarmStorage.getWindowMinutes();
        var state    = Application.Storage.getValue("monitorState");
        if (state == null) { state = 0; }

        // ── Coloured edge ring ────────────────────────────────────────────────
        var ringColor = enabled ? 0x00CC66 : 0x444444;
        dc.setColor(ringColor, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(5);
        dc.drawArc(_cx, _cy, (_cx - 5), Graphics.ARC_COUNTER_CLOCKWISE, 0, 360);
        dc.setPenWidth(1);

        // ── Title ─────────────────────────────────────────────────────────────
        dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, 14, Graphics.FONT_XTINY, "SMART ALARM",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // ── Alarm time ────────────────────────────────────────────────────────
        var ampm        = (hour >= 12) ? "PM" : "AM";
        var displayHour = hour % 12;
        if (displayHour == 0) { displayHour = 12; }
        var timeStr = displayHour.format("%d") + ":" + minute.format("%02d");

        var timeColor = enabled ? Graphics.COLOR_WHITE : 0x666666;
        dc.setColor(timeColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx - 14, _cy - 44, Graphics.FONT_NUMBER_HOT, timeStr,
                    Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(0x999999, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx + 54, _cy - 28, Graphics.FONT_TINY, ampm,
                    Graphics.TEXT_JUSTIFY_LEFT);

        // ── Smart window subtitle ─────────────────────────────────────────────
        dc.setColor(0x4488FF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + 10, Graphics.FONT_XTINY,
                    "Smart window: -" + window + " min",
                    Graphics.TEXT_JUSTIFY_CENTER);

        // ── Day-of-week indicators ────────────────────────────────────────────
        _drawDayDots(dc, days, _cy + 38);

        // ── Alert mode icon ───────────────────────────────────────────────────
        var modeLabels = ["Sound+Vibe", "Sound only", "Vibe only"];
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + 68, Graphics.FONT_XTINY, modeLabels[mode],
                    Graphics.TEXT_JUSTIFY_CENTER);

        // ── Status ────────────────────────────────────────────────────────────
        var statusText  = "";
        var statusColor = 0x666666;
        if (enabled) {
            if (state == 1) {
                statusText  = "Monitoring sleep...";
                statusColor = 0x00CC66;
            } else if (state == 2) {
                statusText  = "Alarm fired!";
                statusColor = 0xFF6600;
            } else {
                statusText  = "Armed";
                statusColor = 0x4488FF;
            }
        } else {
            statusText = "Off";
        }
        dc.setColor(statusColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h - 42, Graphics.FONT_XTINY, statusText,
                    Graphics.TEXT_JUSTIFY_CENTER);

        // ── Hint ──────────────────────────────────────────────────────────────
        dc.setColor(0x333333, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _h - 26, Graphics.FONT_XTINY, "SELECT to configure",
                    Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Draws seven small circles with day-letter labels.
    // Active days are bright green; inactive days are dark grey.
    private function _drawDayDots(dc as Graphics.Dc, days as Number, y as Number) as Void {
        var labels  = ["S", "M", "T", "W", "T", "F", "S"];
        var spacing = 30;
        var startX  = _cx - (spacing * 3);

        for (var i = 0; i < 7; i++) {
            var x       = startX + i * spacing;
            var active  = (days & (1 << i)) != 0;

            // Circle background
            dc.setColor(active ? 0x00AA55 : 0x222222, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y + 10, 12);

            // Letter
            dc.setColor(active ? Graphics.COLOR_WHITE : 0x555555,
                        Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, Graphics.FONT_XTINY, labels[i],
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}