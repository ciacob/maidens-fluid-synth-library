package eu.claudius.iacob.synth.sound.map {
import eu.claudius.iacob.synth.sound.map.TrackObject;

public class TrackObjectWindow {

    private var _trackObject:TrackObject;
    private var _startTime:int;
    private var _timeSpan:int;

    /**
     * Helper class to represent the position a TrackObject currently holds on a Track.
     * @param   trackObject
     *          The TrackObject information is related with.
     *
     * @param   startTime
     *          The number of the millisecond the TrackObject is placed on the Track.
     *
     * @param   timeSpan
     *          On how many milliseconds the TrackObject is replicated on the Track.
     */
    public function TrackObjectWindow(trackObject:TrackObject, startTime:int, timeSpan:int) {
        _trackObject = trackObject;
        _startTime = startTime;
        _timeSpan = timeSpan;
    }

    public function get trackObject():TrackObject {
        return _trackObject;
    }

    public function get startTime():int {
        return _startTime;
    }

    public function get timeSpan():int {
        return _timeSpan;
    }
}
}
