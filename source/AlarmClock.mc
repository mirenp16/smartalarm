import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Calendar coordinates use UTC encoding of LOCAL date/time fields. They are
// identifiers, not actual instants. Applying the watch's current offset turns
// them into deadlines; recomputing after an offset change keeps wall times fixed.
class AlarmClock {
    (:productionClock)
    static function now() as Time.Moment { return Time.now(); }

    (:productionClock)
    static function offset(at as Number) as Number {
        var info = Gregorian.info(new Time.Moment(at), Time.FORMAT_SHORT);
        return Gregorian.moment({:year=>info.year, :month=>info.month, :day=>info.day,
            :hour=>info.hour, :minute=>info.min, :second=>info.sec}).value() - at;
    }

    static function wall(at as Number) as Number { return at + offset(at); }
    static function day(at as Number) as Number { return wall(at) / 86400; }
    static function targetKey(day as Number, minutes as Number) as Number {
        return day * 86400 + minutes * 60;
    }
    static function dayBit(day as Number) as Number {
        var info = Gregorian.utcInfo(new Time.Moment(day * 86400), Time.FORMAT_SHORT);
        return 1 << (info.day_of_week - 1);
    }

    // Test clock and offset simulate real transitions without changing macOS.
    (:testSupport) private static var _now as Number? = null;
    (:testSupport) private static var _offset as Number? = null;
    (:testSupport)
    static function setTestTime(at as Number?, offset as Number?) as Void {
        _now = at;
        _offset = offset;
    }
    (:testSupport)
    static function now() as Time.Moment {
        return (_now == null) ? Time.now() : new Time.Moment(_now as Number);
    }
    (:testSupport)
    static function offset(at as Number) as Number {
        if (_offset != null) { return _offset as Number; }
        var info = Gregorian.info(new Time.Moment(at), Time.FORMAT_SHORT);
        return Gregorian.moment({:year=>info.year, :month=>info.month, :day=>info.day,
            :hour=>info.hour, :minute=>info.min, :second=>info.sec}).value() - at;
    }
}
