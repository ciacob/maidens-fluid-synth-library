package eu.claudius.iacob.synth.sound.map {

import ro.ciacob.utils.Strings;

public class Track {

    private var _label:String;
    private var _id:String;
    private var _preset:int;
    private var _baseVolume:int;
    private var _basePan:int;
    private var _baseVelocity:int;
    private var _isMuted:Boolean;
    private var _isSoloed:Boolean;
    private var _trackObjects:Array;

    /**
     * The Track is a unidimensional sparse Array of TrackObjects.
     *
     * A variable number of Tracks (but at least one) are expected to be added to a parent Timeline, and they are
     * time-synchronized with a one millisecond granularity. When reading back the Timeline, all added tracks
     * are inspected simultaneously, for each millisecond the Timeline play-head enters into.
     * @constructor
     * @see eu.claudius.iacob.synth.sound.map.Timeline
     *
     * Apart for being individual and synchronized containers for TrackObjects, Tracks present functionality you would
     * normally expect in a multi-track MIDI editor, such as muting, solo-ing or globally setting volume, pan or
     * velocity.
     *
     * @param label
     * @param preset
     * @param id
     * @param baseVolume
     * @param basePan
     * @param baseVelocity
     */
    public function Track(label:String, preset:int, id:String = null,
                          baseVolume:int = 63, basePan:int = 63, baseVelocity:int = 63) {

        _label = label;
        _id = (id || Strings.UUID);
        _preset = preset;
        _baseVolume = baseVolume;
        _basePan = basePan;
        _baseVelocity = baseVelocity;
        _trackObjects = [];
    }

    /**
     * Arbitrary, short-lived data to be associated with this track. This can be used, e.g., to aid locating a Track
     * by temporarily storing its internal index in the collection of Tracks. Data stored here should only be considered
     * relevant if read immediately after being written.
     */
    public var data : Object;

    public function get id():String {
        return _id;
    }

    public function get label():String {
        return _label;
    }

    public function set label(value:String):void {
        _label = value;
    }

    public function get preset():int {
        return _preset;
    }

    public function set preset(value:int):void {
        _preset = value;
    }

    public function get baseVolume():int {
        return _baseVolume;
    }

    public function set baseVolume(value:int):void {
        _baseVolume = value;
    }

    public function get basePan():int {
        return _basePan;
    }

    public function set basePan(value:int):void {
        _basePan = value;
    }

    public function get baseVelocity():int {
        return _baseVelocity;
    }


    public function get isMuted():Boolean {
        return _isMuted;
    }

    public function get isSoloed():Boolean {
        return _isSoloed;
    }

    public function set baseVelocity(value:int):void {
        _baseVelocity = value;
    }

    public function mute():void {
        _isMuted = true;
    }

    public function unMute():void {
        _isMuted = false;
    }

    public function solo():void {
        _isSoloed = true;
    }

    public function unSolo():void {
        _isSoloed = false;
    }

    public function get numFrames():uint {
        return _trackObjects.length;
    }

    /**
     * Adds a TrackObject, optionally specifying a start and a timespan.
     *
     * If no start time is specified, the TrackObject is appended next to the last TrackObject found on the track.
     * If a timespan is not specified, 50 milliseconds is assumed.
     *
     * NOTES:
     * TrackObjects on a Track cannot overlap. Adding a TrackObject to an already occupied area overrides existing
     * information, completely ERASING any TrackObjects previously found there.
     *
     * TrackObjects do not usually "do something" on each millisecond of their declared time span; most of the time,
     * they "turn on" something at the start of that period, and "turn it off" at tis end. Repeatedly marking a
     * TrackObject on the Timeline for every frame of its timespan is done to:
     * (1) provide an easier method of locating TrackObjects that are relevant for a set period of time;
     * (2) make possible a coarser (and faster) Track scanning procedure (e.g., scanning every 100th index to locate an
     * TrackObject will be faster than scanning every single index).
     *
     * Tracks use unsigned integers to store indices, therefore a Track can store at most 2^32 - 1 indices. That gives a
     * maximum of 4294967295 representable milliseconds (roughly 50 days). Therefore, a track (and implicitly the
     * Timeline) cannot represent durations longer than that.
     *
     * @param trackObject
     * @param startTime
     * @param timeSpan
     */
    public function addObject(trackObject:TrackObject, startTime:int = -1, timeSpan:int = 50):void {

        if (startTime == -1) {
            startTime = _trackObjects.length;
        }
        var endTime:int = (startTime + timeSpan);
        var i : int = startTime;
        for (i; i < endTime; i++) {
            _trackObjects[i] = trackObject;
        }
    }

    /**
     * Returns a (possibly empty) list containing all the TrackObjects found to be registered on this Track inside the
     * time window defined by given `startTime` and optional `searchWindowWidth`. For performance reasons, a higher
     * granularity can be specified, at the expense of possibly missing out TrackObjects that have a very short
     * timespan set.
     *
     * @param   startTime
     *          The start point, in milliseconds, to begin searching from.
     *
     * @param   searchWindowWidth
     *          How much further from `startTime` to search, in milliseconds. Optional, defaults to 50 milliseconds.
     *
     * @param   searchGranularity
     *          The step, in milliseconds, to advance while searching. Optional, defaults to 1 millisecond. If it is
     *          known that the Timeline is populated with TrackObjects of relatively long timespan, it may make sense to
     *          increase this value to speed up searches. A large granularity runs the risk of missing out TrackObjects
     *          with short time spans.
     *
     * @return  A (possibly empty) Vector with TrackObject instances.
     */
    public function getObjectsAt(startTime:int, searchWindowWidth:Number = 50, searchGranularity:int = 1):Vector.<TrackObject> {
        var result:Vector.<TrackObject> = new Vector.<TrackObject>();
        var lastFound:TrackObject = null;
        var endTime:int = (startTime + searchWindowWidth);
        var objectAtCurrPosition:*;
        for (var i:int = startTime; i < endTime; i += searchGranularity) {
            objectAtCurrPosition = _trackObjects[i];
            if (objectAtCurrPosition !== undefined) {
                if (objectAtCurrPosition !== lastFound) {
                    lastFound = objectAtCurrPosition;
                    result.push (objectAtCurrPosition as TrackObject);
                }
            }
        }
        return result;
    }

    /**
     * Scans the entire track for the given TrackObject and returns information regarding its whereabouts, packed in an
     * TrackObjectWindow instance.
     *
     * @param   trackObject
     *          The TrackObject to scan for.
     *
     * @param   useFastScan
     *          Optional, default false. Whether to attempt to "cut corners" by using a coarser scan. If the TrackObject
     *          is known beforehand to have a large timespan, this can save CPU by not looking in every single position
     *          on the Track. Can have adverse speed effects for TrackObjects that have a small timespan, because, on
     *          failure to locate them using a coarse scan, several, more thorough scans will be employed (down to a
     *          full scan), which might actually double or triple the time needed to retrieve the item, to the point
     *          where it might cost more time than if full scan was employed from the start.
     *
     * @return  An instance of the TrackObjectWindow class, that contains information about the TrackObject's start time
     *          and timespan. Returns `null` on failure to locate the TrackObject.
     */
    public function getObjectWindow (trackObject : TrackObject, useFastScan : Boolean = false) : TrackObjectWindow {
        var objectId : String = trackObject.id;
        if (useFastScan) {
            return (_doScanFor (objectId, 1000) ||
                    _doScanFor (objectId, 500) ||
                    _doScanFor (objectId, 100) ||
                    _doScanFor (objectId));
        }
        return _doScanFor (objectId);
    }

    /**
     * Clears the portion of this track that was previously allocated to any of the provided `trackObjects`, from their
     * start time, up to their full time span. Cleaning puts `undefined` in all the affected slots, and right
     * trims the internal storage accordingly (so that it has no trailing empty slots).
     * @param trackObjects
     */
    public function clearObjects(trackObjects:Vector.<TrackObject>):void {
        var i : int;
        var numObjects : int = trackObjects.length;
        var trackObject : TrackObject;
        var trackObjectWindow : TrackObjectWindow;
        var startTime : int;
        var timeSpan : int;
        var endTime : int;
        var j : int;
        var haveTrailingSpace : Boolean;
        var trimSize : int;
        for (i = 0; i < numObjects; i++) {
            trackObject = trackObjects[i];
            trackObjectWindow = getObjectWindow(trackObject, true);
            if (trackObjectWindow) {
                startTime = trackObjectWindow.startTime;
                timeSpan = trackObjectWindow.timeSpan;
                endTime = (startTime + timeSpan);

                // TODO: FIXME: rethink the logic for trimming the trailing space.
                for (j = startTime; j < endTime; j++) {
                    _trackObjects[j] = undefined;
                }
                if (endTime == _trackObjects.length - 1) {
                    haveTrailingSpace = true;
                    trimSize = timeSpan;
                }
            }
        }
        if (haveTrailingSpace) {
            _trackObjects.length -= trimSize;
        }
    }

    /**
     * Performs the actual work of scanning the Track for a TrackObject with a particular id.
     * @param   id
     *          The TrackObject id to look for.
     *
     * @param   granularity
     *          Optional, defaults to `1`. How thoroughly to scan: `1` (the default) checks each and every
     *          Track position, while greater value trade scan accuracy for speed (e.g., `1000` only checks
     *          every 1000th position).
     *
     * @return  A TrackObjectWindow instance with information about the placement of the TrackObject that matches
     *          the given `id`, or `null` if there is no match (which can be either because there really is
     *          no TrackObject with that id on the track, or scan was too coarse, i.e., granularity was
     *          greater than the TrackObject's timespan).
     */
    private function _doScanFor (id : String, granularity : int = 1) : TrackObjectWindow {
        var endTime : int = _trackObjects.length;
        var objectAtCurrPosition:*;
        var tmpObject :*;
        var trackObject : TrackObject;
        var tmpTrackObject : TrackObject;
        var startTime : int;
        var timeSpan : int;
        var i : int;
        var j : int;
        for (i = 0; i < endTime; i += granularity) {
            objectAtCurrPosition = _trackObjects[i];
            if (objectAtCurrPosition !== undefined) {
                trackObject = (objectAtCurrPosition as TrackObject);

                // If we found a TrackObject with matching id, then we must work
                // backward and forward to count all its adjacent occurrences
                // (this will give us its start time and timespan).
                if (trackObject.id == id) {
                    startTime = i;
                    timeSpan = 1;

                    // Search backward from current position
                    j = (i-1);
                    while (j >= 0) {
                        tmpObject = _trackObjects[j];
                        if (tmpObject !== undefined) {
                            tmpTrackObject = (tmpObject as TrackObject);
                            if (tmpTrackObject.id == id) {
                                startTime--;
                                timeSpan++;
                                j--;
                            } else {
                                break;
                            }
                        } else {
                            break;
                        }
                    }

                    // Search forward from current position
                    j = (i+1);
                    while (j < _trackObjects.length) {
                        tmpObject = _trackObjects[j];
                        if (tmpObject !== undefined) {
                            tmpTrackObject = (tmpObject as TrackObject);
                            if (tmpTrackObject.id == id) {
                                timeSpan++;
                                j++;
                            } else {
                                break;
                            }
                        } else {
                            break;
                        }
                    }

                    // Return findings
                    return new TrackObjectWindow (trackObject, startTime, timeSpan);
                }
            }
        }
        return null;
    }
}
}
