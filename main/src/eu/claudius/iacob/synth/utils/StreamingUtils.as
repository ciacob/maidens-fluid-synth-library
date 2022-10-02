package eu.claudius.iacob.synth.utils {
import eu.claudius.iacob.synth.constants.OperationTypes;
import eu.claudius.iacob.synth.constants.PayloadKeys;
import eu.claudius.iacob.synth.constants.SynthCommon;
import eu.claudius.iacob.synth.events.PlaybackPositionEvent;
import eu.claudius.iacob.synth.events.SystemStatusEvent;
import eu.claudius.iacob.synth.sound.generation.SynthProxy;

import flash.events.EventDispatcher;
import flash.events.IEventDispatcher;
import flash.utils.ByteArray;

import ro.ciacob.utils.Strings;
import ro.ciacob.utils.constants.CommonStrings;

/**
 * Helper class that operates the given SynthProxy instance the way that it streams the audio rendering process.
 */
public class StreamingUtils extends EventDispatcher {

    public static const MIN_BUFFER_LENGTH:uint = 1000;
    public static const MIN_AVG_RENDERING_SPEED:Number = 1.1;
    public static const NUM_CHUNKS_TO_AVERAGE:uint = 4;
    public static const NUM_MIN_ADDITIONAL_WORKERS:uint = 1;
    public static const DROPOUT_BUFFER_INCREASE:Number = 0.15;

    private static const EARLIEST_SEEK_POSITION:String = 'earliestSeekPosition';
    private static const TYPE_SYNTH_INSTRUCTION_TRACK:String = 'typeSynthInstructionTrack';
    private static const TYPE_ANNOTATION_TRACK:String = 'typeAnnotationTrack';

    // Configuration variables
    private var _proxy:SynthProxy;
    private var _tracks:Array;
    private var _autoPlayback:Boolean;
    private var _autoResume:Boolean;
    private var _maxNumWorkers:uint;
    private var _minBufferSize:uint = MIN_BUFFER_LENGTH;

    // Status variables
    private var _numWorkers:uint = NUM_MIN_ADDITIONAL_WORKERS;
    private var _bufferSize:uint = _minBufferSize;
    private var _renderFrom:uint;
    private var _renderTo:uint;
    private var _percentStreamingDone:Number = 0;
    private var _streamingInProgress:Boolean;
    private var _isPlaybackInProgress:Boolean;
    private var _safeToPlayFrom:uint = int.MAX_VALUE;
    private var _safeToPlayTo:uint = 0;
    private var _playheadAt:uint;
    private var _haveDropout:Boolean;
    private var _numDropouts:uint = 0;
    private var _minAvgRenderingSpeed:Number = MIN_AVG_RENDERING_SPEED;
    private var _isBufferSizeLocked:Boolean;
    private var _speedMeasurements:Array = [];

    // Internal logic variables
    private var _privateClient:IEventDispatcher;
    private var _soundsCache:Object;
    private var _sessionId:String;
    private var _workerBytes:ByteArray;
    private var _renderedAudioStorage:ByteArray;
    private var _totalNumInstructions:uint;
    private var _numInstructionsDone:uint;
    private var _parallelRenderer:AudioParallelRenderer;


    /**
     * Helper class that operates the given SynthProxy instance the way that it streams the audio rendering process.
     * That is, instead of rendering all the audio entirely before playback becomes available, the proxy will now render
     * it in chunks, dispatching progress reports via status events, and will begin playback as soon as there is enough
     * rendered material and enough rendering speed.
     *
     * @param   workerBytes
     *          A ByteArray containing the bytes of the SWF file the AudioWorker.as class has been compiled into.
     *          Each additional background worker this class uses will be created out of the provided workerBytes.
     *
     * @param   proxy
     *          The SynthProxy instance the class will control.
     *
     * @param   autoPlayback
     *          Whether to start playback as soon as all the conditions for starting playback are met (i.e., minimum
     *          average rendering speed, or buffer full). Optional, defaults to `true`.
     *
     * @param   autoResume
     *          Whether to resume playback (after a dropout caused by buffer under-run) as soon as the conditions for
     *          starting playback are met (again). Optional, defaults to `true`.
     *
     * @param   maxNumWorkers
     *          The maximum number of actionscript Workers (beside the "main", or "primordial" Worker) to attempt to
     *          employ, in order to speed up rendering. Optional, defaults to `1`.
     *          NOTE: at least one additional Worker will always be used, or else playback could not be engaged while
     *          rendering.
     *
     * @constructor
     */
    public function StreamingUtils(workerBytes:ByteArray, proxy:SynthProxy, autoPlayback:Boolean = true,
                                   autoResume:Boolean = true, maxNumWorkers:uint = 1):void {
        _workerBytes = workerBytes;
        _proxy = proxy;
        _autoPlayback = autoPlayback;
        _autoResume = autoResume;
        _maxNumWorkers = Math.max(NUM_MIN_ADDITIONAL_WORKERS, maxNumWorkers);
    }

    /**
     * See @constructor for details.
     */
    public function get proxy():SynthProxy {
        return _proxy;
    }

    /**
     * A semi-shallow clone of the `tracks` argument the `stream()` function was called with. See `stream()` for details.
     * This property will be `null` if `stream()` was never called before.
     */
    public function get tracks():Array {
        return _tracks;
    }

    /**
     * See @constructor for details.
     */
    public function get autoPlayback():Boolean {
        return _autoPlayback;
    }

    public function set autoPlayback(value:Boolean):void {
        _autoPlayback = value;
    }

    /**
     * See @constructor for details.
     */
    public function get autoResume():Boolean {
        return _autoResume;
    }

    public function set autoResume(value:Boolean):void {
        _autoResume = value;
    }

    /**
     * See @constructor for details.
     */
    public function get maxNumWorkers():uint {
        return _maxNumWorkers;
    }

    public function set maxNumWorkers(value:uint):void {
        _maxNumWorkers = value;
    }

    /**
     * The ByteArray sound was rendered to. This is updated as the streaming progresses.
     */
    public function get renderedAudioStorage():ByteArray {
        return _renderedAudioStorage;
    }

    /**
     * The minimum "buffer length" (i.e., number of milliseconds between current playhead position and the end of the
     * rendered area) that must be met for this class to consider automatically starting (or resuming) playback.
     *
     * NOTES:
     * - the minimum average rendering speed must also be met.
     * - playback can also start/resume when the "buffer is full", that is, once all the "due" audio material has been
     *   fully rendered.
     * - failure to meet this criteria does not cause the playback to STOP (which is only caused by a "buffer under-run"
     *   situation, i.e., the playhead is about to enter an area that hasn't been rendered yet), but it does cause it
     *   not to automatically RESUME.
     */
    public function get minBufferSize():uint {
        return _minBufferSize;
    }

    public function set minBufferSize(value:uint):void {
        _minBufferSize = value;
    }

    /**
     * The minimum "average rendering speed" (i.e., the average time it takes for an audio chunk to be rendered, divided
     * by that audio chunk intrinsic length, both in milliseconds) that must be met for this class to consider
     * automatically starting (or resuming) playback. The average is computed based on the performance of the last
     * `NUM_CHUNKS_TO_AVERAGE` chunks.
     *
     * NOTES:
     * - the minimum buffer length must also be met.
     * - playback can also start/resume when the "buffer is full", that is, once all the "due" audio material has been
     *   fully rendered.
     * - failure to meet this criteria does not cause the playback to STOP (which is only caused by a "buffer under-run"
     *   situation, i.e., the playhead is about to enter an area that hasn't been rendered yet), but it does cause it
     *   not to RESUME, if it gets stopped.
     */
    public function get minAvgRenderingSpeed():Number {
        return _minAvgRenderingSpeed;
    }

    public function set minAvgRenderingSpeed(value:Number):void {
        _minAvgRenderingSpeed = value;
    }

    /**
     * Actually begins rendering chunks of audio; dispatches SystemStatusEvents while progressing, and may cause
     * playback to automatically start or resume (based on the two relevant properties).
     *
     * @param   sounds
     *          An Object containing ByteArray instances, with each ByteArray containing the bytes loaded from a sound
     *          font file. The ByteArrays are indexed based on the General MIDI patch number that represents the musical
     *          instrument emulated by the loaded sound font file. E.g., the samples for a Violin sound would reside in
     *          a file called "40.sf2" (the file must not contain other sounds), and would be loaded in a ByteArray that
     *          gets stored under index `40` in the sounds cache Object: that is because, in the GM specification,
     *          Violin has patch number 40.
     *          NOTE: You would typically produce the value for the `sounds` argument by using the SoundLoader helper
     *          class (eu.claudius.iacob.synth.utils.SoundLoader).
     *
     * @param   tracks
     *          Multidimensional Array that describes the music to be rendered as an ordered succession of instructions
     *          the synthesizer must execute. See `SynthProxy.preRenderAudio()`.
     *
     * @param   privateClient
     *          An `IEventDispatcher` implementor that is running the `stream` process in a "private" context. Optional;
     *          when given, all SystemStatusEvents this class produces are dispatched exclusively  on the given
     *          `privateClient` instance, and no playback is ever engaged.
     */
    public function stream(sounds:Object, tracks:Array, privateClient:IEventDispatcher = null):void {
        var report:ProgressReport;
        var annotationTracks:Array;

        // If streaming was already in progress, report it and do nothing.
        if (_streamingInProgress) {
            report = new ProgressReport(
                    ProgressReport.STATE_CANNOT_STREAM,
                    ProgressReport.SUBSTATE_STREAMING_IN_PROGRESS);
            _dispatcher.dispatchEvent(new SystemStatusEvent(report));
            return;
        }

        // If there was no content to stream, report it and do nothing.
        if (_areTracksEmpty(tracks)) {
            report = new ProgressReport(
                    ProgressReport.STATE_CANNOT_STREAM,
                    ProgressReport.SUBSTATE_EMPTY_TRACKS);
            _dispatcher.dispatchEvent(new SystemStatusEvent(report));
            return;
        }

        // Engage private mode if requested.
        _privateClient = privateClient;

        // Ensure playback is stopped.
        _proxy.stopStreamedPlayback();
        _proxy.stopPrerenderedPlayback(true);

        // Reset all flags and values.
        _totalNumInstructions = _countInstructionsOf(tracks);
        _numInstructionsDone = 0;
        _streamingInProgress = true;
        var tracksClone:Array = _cloneTracks(tracks);
        var split:Object = _splitTracksByType(tracksClone);
        _tracks = split[TYPE_SYNTH_INSTRUCTION_TRACK];
        annotationTracks = split[TYPE_ANNOTATION_TRACK];
        _renderFrom = 0;
        _renderTo = _bufferSize;
        _playheadAt = 0;
        _safeToPlayFrom = 0;
        _safeToPlayTo = 0;
        _speedMeasurements.length = 0;
        _bufferSize = _minBufferSize;
        _percentStreamingDone = 0;
        _isPlaybackInProgress = false;
        _haveDropout = false;
        _numDropouts = 0;
        _isBufferSizeLocked = false;

        // (Re) initialize the audio storage.
        if (!_renderedAudioStorage) {
            _renderedAudioStorage = _proxy.audioStorage;
        }
        _renderedAudioStorage.clear();

        // Start a new session.
        _soundsCache = sounds;
        _sessionId = Strings.UUID;

        // Render all annotations in the main process.
        _proxy.preRenderAudio(_soundsCache, annotationTracks, false, _sessionId);

        // Render all synth instructions incrementally, in separate processes.
        report = new ProgressReport(ProgressReport.STATE_STREAMING_START);
        _dispatcher.dispatchEvent(new SystemStatusEvent(report));
        _streamNextChunk();
    }

    /**
     * Breaks up the process, so the next scheduled chunk to be streamed is never processed. Useful, e.g., for
     * implementing the scenario where the user decides to exit the application before streaming some long musical
     * content entirely.
     */
    public function cancelStreaming():void {
        if (_streamingInProgress) {
            _streamingInProgress = false;
        }
    }

    /**
     * Allows the user to externally indicate that he would not want playback to be resumed after a specific dropout.
     * This would likely be achieved by clicking the "stop playback", in the UI (as having a dropout would only visually
     * engage the "pause playback" button, thus leaving the "stop playback" button available).
     */
    public function clearDropoutState():void {
        _haveDropout = false;
    }

    /**
     * Convenience internal getter that returns the `_privateClient` instance when given, or the current StreamingUtils
     * instance otherwise; used to decide where exactly the SystemStatus events are to be dispatched (the idea being
     * that, when a `_privateClient` instance is in effect, all event to be only dispatched there).
     */
    private function get _dispatcher():IEventDispatcher {
        return (_privateClient || this);
    }

    /**
     * Performs a semi-shallow clone of given `tracks` Array, where each "track" is a shallow clone of its original
     * counterpart (meaning that the track objects themselves are not clones, but instances of the same
     * objects as in the original track).
     *
     * @param   tracks
     *          Multidimensional Array that describes the music to be rendered as an ordered succession of instructions
     *          the synthesizer must execute. See `SynthProxy.preRenderAudio()`.
     *
     * @return  The cloned "tracks".
     */
    private function _cloneTracks(tracks:Array):Array {
        var clone:Array = [];
        var i:int;
        var numTracks:uint = tracks.length;
        var track:Array;
        for (i = 0; i < numTracks; i++) {
            track = (tracks[i] as Array);
            clone[i] = track.concat();
        }
        return clone;
    }

    /**
     * Helper method to evaluate whether given "tracks" are devoid of any musical content.
     * @param   tracks
     *          Multidimensional Array that describes the music to be rendered as an ordered succession of instructions
     *          the synthesizer must execute. See `SynthProxy.preRenderAudio()`.
     *
     * @return  `True` if given `tracks` are to be considered musically empty; `false` if there is content.
     */
    private function _areTracksEmpty(tracks:Array):Boolean {
        var i:int;
        var numTracks:uint = tracks.length;
        var track:Array;
        for (i = 0; i < numTracks; i++) {
            track = (tracks[i] as Array);
            if (track.length > 0) {
                return false;
            }
        }
        return true;
    }

    /**
     * Causes the synth proxy controlled by this class to attempt playback.
     *
     * @return `True` if playing back is possible (and was successfully engaged), `false` otherwise.
     */
    private function _engagePlayback():Boolean {

        // Playback will never be engaged when running in "private" mode.
        if (_privateClient) {
            return false;
        }

        // If NOT running in "private" mode, playback will be engaged whenever appropriate.
        if (!_isPlaybackInProgress) {
            if (_playheadAt >= _safeToPlayFrom && _playheadAt < _safeToPlayTo) {
                if (_playheadAt == 0) {
                    _proxy.audioStorage.position = 0;
                }
                var tmp:Function = function (event:PlaybackPositionEvent):void {
                    _proxy.removeEventListener(PlaybackPositionEvent.PLAYBACK_POSITION_EVENT, tmp);
                    var report:ProgressReport = new ProgressReport(
                            ProgressReport.STATE_PLAYING,
                            ProgressReport.SUBSTATE_STREAMING_IN_PROGRESS
                    );
                    _dispatcher.dispatchEvent(new SystemStatusEvent(report));
                    _isPlaybackInProgress = true;
                }
                _proxy.addEventListener(PlaybackPositionEvent.PLAYBACK_POSITION_EVENT, tmp);
                _proxy.addEventListener(PlaybackPositionEvent.PLAYBACK_POSITION_EVENT, _onPLayBackPositionChanged);
                _proxy.playBackStreamedAudio();
                return true;
            }
        }
        return false;
    }

    /**
     * Convenience method to evaluate whether playback could legitimately be engaged.
     */
    private function _shouldEngagePlayback():Boolean {
        return (!_isPlaybackInProgress && (_autoPlayback || (_autoResume && _haveDropout)));
    }

    /**
     * Cuts as many objects from the internally available "tracks" clone to at least cover the current _bufferSize.
     * Based on how many "ties" there are in the musical content, the rendered content can be of greater length. When
     * the rendering is completed, several key performance indicators are analyzed, based on which the following can
     * (or can not) happen:
     * - playback is started (or resumed), if the class was configured this way;
     * - the `_bufferSize` is increased;
     *
     * Regardless of the analysis result, the following always happen:
     * - a report is broadcasted via a status event;
     * - streaming the next chunk is scheduled.
     */
    private function _streamNextChunk():void {
        var report:ProgressReport;
        if (!_streamingInProgress) {
            report = new ProgressReport(
                    ProgressReport.STATE_CANNOT_STREAM,
                    ProgressReport.SUBSTATE_STREAMING_CANCELLED
            );
            _dispatcher.dispatchEvent(new SystemStatusEvent(report));
            return;
        }

        if (!_areTracksEmpty(_tracks)) {
            // Initialize the parallel renderer if not done so already.
            if (!_parallelRenderer) {
                _parallelRenderer = new AudioParallelRenderer(_workerBytes, _onChunkDone, _onParallelRendererError);
            }

            // If there is still content left to render, we slice the next logical chunk of the cloned "tracks", and
            // send it over for rendering.
            var chunk:Array = _getTracksSlice(_tracks, _renderFrom, _renderTo);
            _parallelRenderer.positionBeforeRendering = -1;
            if (chunk[EARLIEST_SEEK_POSITION] !== undefined) {
                _parallelRenderer.positionBeforeRendering = (chunk[EARLIEST_SEEK_POSITION] as int);
            }
            _parallelRenderer.timeBeforeRendering = (new Date()).getTime();
            _parallelRenderer.assignWork(chunk, _renderedAudioStorage, _sessionId, _soundsCache);
        } else {

            // If there is no content left to render, we are done. We remove the playback limit in order not to trim
            // out any "tail" the sound might have, reset relevant flags, report back, and engage playback
            // if requested and not done already.
            _safeToPlayTo = int.MAX_VALUE;
            _streamingInProgress = false;
            _percentStreamingDone = 1;
            report = new ProgressReport(
                    ProgressReport.STATE_STREAMING_DONE,
                    ProgressReport.SUBSTATE_NOTHING_TO_DO,
                    null,
                    null,
                    _percentStreamingDone
            );
            _dispatcher.dispatchEvent(new SystemStatusEvent(report));

            // Start or resume playback if appropriate.
            if (_shouldEngagePlayback()) {
                _engagePlayback();
            }

            // Drop out of "private" mode if it was engaged.
            _privateClient = null;
        }
    }

    /**
     * Executing when rendering a chunk (or "slice") of the tracks has been completed.
     * TODO: document.
     * TODO: implement.
     */
    private function _onChunkDone(renderer:AudioParallelRenderer):void {

        // Analyze rendering performance; update status and adjust streaming settings to improve performance of
        // rendering future chunks.
        var positionAfterRendering:uint = _renderedAudioStorage.length;
        var timeAfterRendering:Number = (new Date()).getTime();

        var analysisResult:AnalysisResult = null;
        if (renderer.positionBeforeRendering != -1) {
            analysisResult = _analyzePerformance(
                    renderer.positionBeforeRendering, positionAfterRendering,
                    renderer.timeBeforeRendering, timeAfterRendering,
                    _speedMeasurements, _numDropouts
            );
            _updateStreamingParams(analysisResult);
        }

        // Update playback-safe boundaries, and engage playback if appropriate.
        if (_renderFrom < _safeToPlayFrom) {
            _safeToPlayFrom = _renderFrom;
        }
        if (_renderTo > _safeToPlayTo) {
            _safeToPlayTo = _renderTo;
        }

        // Start playing back if appropriate.
        if (analysisResult) {
            if (_speedMeasurements.length >= NUM_CHUNKS_TO_AVERAGE &&
                    analysisResult.canEngagePlayback && _shouldEngagePlayback()) {
                _engagePlayback();
            }
        }

        // Report progress to the calling code.
        _numInstructionsDone += _countInstructionsOf(renderer.tracks);
        var percentDone:Number = (_numInstructionsDone / _totalNumInstructions);
        if (_percentStreamingDone != percentDone) {
            _percentStreamingDone = percentDone;
            var report:ProgressReport = new ProgressReport(
                    ProgressReport.STATE_STREAMING_PROGRESS,
                    ProgressReport.SUBSTATE_RENDERING_AUDIO,
                    null,
                    null,
                    _percentStreamingDone
            );
            _dispatcher.dispatchEvent(new SystemStatusEvent(report));
        }

        // Schedule the next rendering session.
        _renderFrom = _renderTo;
        _renderTo += _bufferSize;
        _streamNextChunk();
    }

    /**
     * Executed when the audio parallel renderer encountered an error while rendering given (MIDI) tracks into audio.
     * @param renderer
     */
    private function _onParallelRendererError(renderer:AudioParallelRenderer):void {
        _streamingInProgress = false;
        var report:ProgressReport = new ProgressReport(
                ProgressReport.STATE_CANNOT_STREAM,
                ProgressReport.SUBSTATE_ERROR,
                _dumpObject(renderer.errorDetail)
        );
        _dispatcher.dispatchEvent(new SystemStatusEvent(report));
    }

    /**
     * Executed during playback as the virtual playhead is updating its position.
     * @param event
     */
    private function _onPLayBackPositionChanged(event:PlaybackPositionEvent):void {
        _playheadAt = event.position;
        var report:ProgressReport;

        // We also get "playback position events" from the proxy when playback is rewind, which we want to ignore,
        // and definitely not consider them when assessing dropouts.
        if (_isPlaybackInProgress) {
            if (_playheadAt < _safeToPlayFrom || _playheadAt > _safeToPlayTo) {
                _haveDropout = true;
                _numDropouts++;
                _proxy.stopStreamedPlayback();
                _isPlaybackInProgress = false;

                // We increase the buffer in order to lower the chance of future dropouts to occur;
                // we also leave it unlocked, so that the performance analysis may increase it as well, if
                // it sees fit.
                _bufferSize += (_bufferSize * (DROPOUT_BUFFER_INCREASE * _numDropouts));
                _isBufferSizeLocked = false;

                // Notify the client code of the fact that a dropout occurred.
                report = new ProgressReport(
                        ProgressReport.STATE_CANNOT_STREAM,
                        ProgressReport.SUBSTATE_DROPOUT,
                        null,
                        ('playhead at: ' + _playheadAt.toFixed(2) + ' | safe to play from: ' +
                                _safeToPlayFrom.toFixed(2) + ' | safe to play to: ' +
                                _safeToPlayTo.toFixed(2))
                )
                _dispatcher.dispatchEvent(new SystemStatusEvent(report));
                return;
            }
        }
    }

    /**
     * Modifies the internal configuration parameters that govern the streaming process, based on information in the
     * provided `report`.
     *
     * @param   report
     *          AnalysisResult instance containing containing recommendations meant to improve the overall process
     *          speed and efficiency.
     */
    private function _updateStreamingParams(report:AnalysisResult):void {
        if (report.shouldIncreaseBuffer && !_isBufferSizeLocked) {
            _bufferSize += (_bufferSize * report.suggestedBufferIncreaseFactor);
            _isBufferSizeLocked = true;
        }
        if (report.shouldAddWorker && _numWorkers < _maxNumWorkers) {
            // TODO: engage new worker.
        }
    }

    /**
     * Intelligently cuts and returns a subset of the track objects available in the given `tracks`, the way that the
     * resulting `tracks chunk` contain instructions that make sense from a synthesizer perspective. The following rules
     * apply when slicing tracks:
     *
     * - All instructions of `TYPE_SEEK_TO` whose `TIME` falls within the window described by `sliceFrom` and
     *   `sliceTo` will be included in the slice, and will open a "slicing session" on the current track.
     *
     * - All instructions of `TYPE_NOTE_ON`, `TYPE_REQUEST_SAMPLES`, or `TYPE_NOTE_OFF` whose ID matches the one of an
     *   already included instruction of `TYPE_SEEK_TO` will be included in the slice.
     *
     * - Including an instruction in the slice actually removes it from its original "tracks" Array (this is safe, since
     *   that Array is a clone, anyway).
     *
     *  - We will not search for matching instructions to include in the slice across the entire "tracks" in the original
     *    Array, since that would waste CPU; the first not matching instruction of `TYPE_SEEK_TO` or will conclude the
     *    search for the respective track.
     *
     * NOTE: all instructions of `TYPE_HIGHLIGHT_SCORE_ITEM` will be routed in bulk to the synthesizer instance
     * that runs in the main thread/worker: they are light and easy to handle on the main thread, and the effort of
     * collecting the resulting annotation tasks across all involved background threads wouldn't pay off.
     *
     * @param   tracks
     *          Multidimensional Array that describes the music to be rendered as an ordered succession of instructions
     *          the synthesizer must execute. See `SynthProxy.preRenderAudio()`. This is expected to be a clone of the
     *          original, and will incrementally be emptied, on each run of this method.
     *
     * @param   sliceFrom
     *          Start of the reference timeframe, in milliseconds. In principle, only instructions dealing with events
     *          occurring AFTER this time are included in the resulting slice.
     *
     * @param   sliceTo
     *          End of the reference timeframe, in milliseconds. In principle, only instructions dealing with events
     *          occurring AT OR BEFORE this time are included in the resulting slice (in practice, tied notes will
     *          extend past this limit).
     *
     * @return  A new Array, containing instructions that chiefly deal with events occurring within the defined
     *          timeframe. Can return an empty Array if the timeframe overlaps an empty area in the original "tracks"
     *          Array. This can sometimes happen due to tied notes extending far beyond the timeframe (so that future
     *          runs of this method will only find the "void" left behind).
     *
     * SIDE EFFECT: stores the earliest of all the seek positions registered, as a static property on the returned
     * Array. The property is accessible under the key of `EARLIEST_SEEK_POSITION`.
     */
    private function _getTracksSlice(tracks:Array, sliceFrom:uint, sliceTo:uint):Array {
        var slice:Array = [];
        var earliestSeekPosition:uint = uint.MAX_VALUE;
        var i:int;
        var numTracks:uint = tracks.length;
        var track:Array;
        var trackSlice:Array;
        var numInstructions:uint;
        var instruction:Object;
        var instructionTime:uint;
        var instructionId:String;
        var sessionId:String;

        track_scope:
                for (i = 0; i < numTracks; i++) {
                    track = (tracks[i] as Array);
                    trackSlice = [];
                    slice.push(trackSlice);

                    sessionId = null;
                    numInstructions = track.length;
                    if (numInstructions > 0) {
                        do {
                            instruction = (track[0] as Object);
                            numInstructions--;
                            instructionId = (instruction[PayloadKeys.ID] as String);
                            switch (instruction[PayloadKeys.TYPE]) {

                                    // "Seek to" instructions are able to open or close slicing
                                    // sessions at track level.
                                case OperationTypes.TYPE_SEEK_TO:
                                    instructionTime = (instruction[PayloadKeys.TIME] as uint);
                                    if (instructionTime < sliceFrom || instructionTime > sliceTo) {
                                        sessionId = null;
                                        continue track_scope;
                                    }
                                    if (instructionTime < earliestSeekPosition) {
                                        earliestSeekPosition = instructionTime;
                                    }
                                    sessionId = instructionId;
                                    trackSlice.push(instruction);
                                    track.shift();
                                    continue; // inside the "do" loop

                                    // "Note on", "request samples" and "note off" instructions all
                                    // depend on the leading "seek to" instruction whose "id" they
                                    // share. They will only be included based on having the correct id.
                                    // The fact that, in the original "tracks" Array, "seek to"
                                    // instructions always precede "note on", "request samples" or
                                    // "note off" instructions is enough to ensure their correct order
                                    // in the slice too.
                                case OperationTypes.TYPE_NOTE_ON:
                                case OperationTypes.TYPE_REQUEST_SAMPLES:
                                case OperationTypes.TYPE_NOTE_OFF:
                                    if (instructionId == sessionId) {
                                        trackSlice.push(instruction);
                                        track.shift();
                                    }
                            }
                        } while (numInstructions > 0);
                    }
                }
        if (earliestSeekPosition != uint.MAX_VALUE) {
            slice[EARLIEST_SEEK_POSITION] = earliestSeekPosition;
        }
        return slice;
    }

    /**
     * Analyzes the rendering process from a performance perspective, based on a number of given key performance
     * indicators. Makes informed decisions regarding the process parameters that could be adjusted in order to improve
     * its speed and efficiency. Also decides how appropriate it is, given the current set of circumstances, to engage
     * playback.
     *
     * @param   positionBeforeRendering
     *          The byte index, inside the internal storage for rendered audio (a ByteArray instance) that was
     *          registered BEFORE rendering started. Helps calculate the length of the rendered audio.
     *
     * @param   positionAfterRendering
     *          The byte index, inside the internal storage for rendered audio (a ByteArray instance) that was
     *          registered AFTER rendering started. Helps calculate the length of the rendered audio.
     *
     * @param   timeBeforeRendering
     *          The time, in milliseconds, registered BEFORE rendering was started. Helps calculate rendering speed.
     *
     * @param   timeAfterRendering
     *          The time, in milliseconds, registered AFTER rendering was started. Helps calculate rendering speed.
     *
     * @param   renderSpeedMeasurements
     *          An Array with previous rendering speed measurements. Helps calculating a mobile average of it.
     *
     * @param   numDropouts
     *          How many dropouts there were since last resetting this indicator. Helps calculate a score of playback
     *          reliability.
     *
     * @return  Packs and returns the analysis result as an instance of the helper class AnalysisResult.
     */
    private static function _analyzePerformance(positionBeforeRendering:uint, positionAfterRendering:uint,
                                                timeBeforeRendering:Number, timeAfterRendering:Number,
                                                renderSpeedMeasurements:Array, numDropouts:uint):AnalysisResult {

        // Compute the current rendering speed.
        var numRenderedBytes:uint = (positionAfterRendering - positionBeforeRendering);
        var numRenderedSamples:uint = Math.floor(numRenderedBytes / SynthCommon.SAMPLE_BYTE_SIZE);
        var numRenderedMsecs:uint = numRenderedSamples / SynthCommon.SAMPLES_PER_MSEC;
        var numElapsedMsecs:uint = (timeAfterRendering - timeBeforeRendering);
        var renderingSpeed:Number = (numRenderedMsecs / numElapsedMsecs);
        renderSpeedMeasurements.push(renderingSpeed);

        // Compute the mobile average of rendering speed, considering the last `NUM_CHUNKS_TO_AVERAGE` chunks (at most).
        var startSlotIndex:int = Math.max(0, renderSpeedMeasurements.length - NUM_CHUNKS_TO_AVERAGE);
        var numSlots:uint = renderSpeedMeasurements.length;
        var numObservedSlots:uint = 0;
        var indexVal:Number;
        var sum:Number = 0;
        for (startSlotIndex; startSlotIndex < numSlots; startSlotIndex++) {
            indexVal = renderSpeedMeasurements[startSlotIndex];
            sum += indexVal;
            numObservedSlots++;
        }
        var avgRenderingSpeed:Number = (sum / numObservedSlots);

        // Compute a buffer increase factor. This will be over unity only if the average rendering speed is smaller than
        // the minimum accepted value.
        var bufferIncreaseFactor:Number = Math.max(1, MIN_AVG_RENDERING_SPEED / avgRenderingSpeed);
        var doIncreaseBuffer:Boolean = (bufferIncreaseFactor > 1);

        // Compute a score for the likeliness of engaging playback.
        var playbackReadyScore:Number = avgRenderingSpeed / (1 + numDropouts);
        var doPlayBack:Boolean = (avgRenderingSpeed >= MIN_AVG_RENDERING_SPEED) && (playbackReadyScore >= 0.5);

        // Decide whether adding a worker could help.
        var doAddWorker:Boolean = (avgRenderingSpeed < MIN_AVG_RENDERING_SPEED);

        // Compile and return the report.
        var report:AnalysisResult = new AnalysisResult(avgRenderingSpeed, doPlayBack, doIncreaseBuffer,
                bufferIncreaseFactor, doAddWorker);
        return report;
    }

    /**
     * Groups given `tracks` in two main categories, namely tracks that contain synth instructions, such as "noteOn",
     * "noteOff", etc., and tracks that contain score annotation instructions, such as "highlight score item", or
     * "unhighlight score item". Empty tracks are not returned in either category.
     *
     * @param   tracks
     *          Expected to be a clone of the `tracks` argument received by the public method `stream`. See `stream()`
     *          for more detail on the argument.
     *
     * @return  An Object with two keys, defined by the constants `TYPE_SYNTH_INSTRUCTION_TRACK` and
     *          `TYPE_ANNOTATION_TRACK`. Both keys hold multidimensional Arrays of the same format as the original
     *          `tracks` argument.
     */
    private function _splitTracksByType(tracks:Array):Object {
        var out:Object = {};
        var synthTracks:Array = [];
        var annotationTracks:Array = [];
        out[TYPE_SYNTH_INSTRUCTION_TRACK] = synthTracks;
        out[TYPE_ANNOTATION_TRACK] = annotationTracks;
        var i:int = 0;
        var numTracks:uint = tracks.length;
        var track:Array;
        var firstInstruction:Object;
        var firstType:String;
        for (i; i < numTracks; i++) {
            track = (tracks[i] as Array);
            if (!track.length) {
                continue;
            }
            firstInstruction = (track[0] as Object);
            firstType = (firstInstruction[PayloadKeys.TYPE] as String);
            if (Strings.isAny(firstType, OperationTypes.TYPE_HIGHLIGHT_SCORE_ITEM,
                    OperationTypes.TYPE_UNHIGHLIGHT_SCORE_ITEM)) {
                annotationTracks.push(track);
            } else {
                synthTracks.push(track);
            }
        }
        return out;
    }

    /**
     * Returns the total number of instructions contained by the given `tracksSlice` (see the `tracks` accessor
     * and the `_getTracksSlice()` method for details).
     *
     * @param   tracksSlice
     *          A portion of a "tracks" organized audio data to count the instructions of.
     *
     * @return  The total number of instructions counted.
     */
    private function _countInstructionsOf(tracksSlice:Array):uint {
        var numInstructions:uint = 0;
        var i:int;
        var numTracks:uint = tracksSlice.length;
        var track:Array;
        for (i = 0; i < numTracks; i++) {
            track = (tracksSlice[i] as Array);
            numInstructions += track.length;
        }
        return numInstructions;
    }

    /**
     * Helper method to produce a read-out of all the properties of a given Object.
     * @param obj
     */
    private function _dumpObject(obj:Object):String {
        if (obj is String) {
            return (obj as String);
        }
        var out:Array = [];
        var key:String;
        var value:String;
        for (key in obj) {
            value = ('' + obj[key]);
            out.push(key + CommonStrings.COLON_SPACE + value);
        }
        return (CommonStrings.NEW_LINE + CommonStrings.TAB + out.join(CommonStrings.NEW_LINE + CommonStrings.TAB));
    }
}
}
