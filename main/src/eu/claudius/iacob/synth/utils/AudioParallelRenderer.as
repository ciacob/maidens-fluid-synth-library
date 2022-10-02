package eu.claudius.iacob.synth.utils {
import flash.events.Event;
import flash.system.MessageChannel;
import flash.system.Worker;
import flash.system.WorkerDomain;
import flash.system.WorkerState;
import flash.utils.ByteArray;

import ro.ciacob.utils.Strings;

public class AudioParallelRenderer {

    private static const NO_SUPPORT:String = 'Concurrency is not supported on this platform.';
    private static const BAD_WORKER:String = 'Given background worker source is invalid. Details: %s';
    private static const EMPTY_WORKER_SOURCE:String = 'ByteArray is null or empty.';
    private static const MISSING_SWF_SIGNATURE:String = 'No SWF header was found.';
    private static const BAD_WORKER_STATE:String = 'Worker state is "%s" (wrong) instead of "%s" (expected).';

    private static const SWF_SIGNATURE_SIZE:uint = 3;
    private static const CWS_SWF_SIGNATURE:String = 'CWS';
    private static const FWS_SWF_SIGNATURE:String = 'FWS';

    // Intrinsic properties
    private var _asyncChain:Vector.<Function>;
    private var _errorDetail:Object;
    private var _canOperate:Boolean;
    private var _$renderer_:AudioParallelRenderer;
    private var _workerSrc:ByteArray;
    private var _main:Worker;
    private var _mainDomain:WorkerDomain;
    private var _worker:Worker;
    private var _workerUid:String;
    private var _mainChannel:MessageChannel;
    private var _workerChannel:MessageChannel;

    // Operational properties
    private var _tracksStorage:ByteArray;
    private var _tracksValue:Array;
    private var _sessionValue:String;
    private var _sessionStorage:ByteArray;
    private var _soundsMapValue:Object;
    private var _soundsMapStorage:ByteArray;
    private var _renderedAudioStorage:ByteArray;
    private var _onDoneCallback:Function;
    private var _onErrorCallback:Function;

    /**
     *
     * @param workerSrc
     * @param onDoneCallback
     * @param onErrorCallback
     */
    public function AudioParallelRenderer(workerSrc:ByteArray, onDoneCallback:Function, onErrorCallback:Function) {
        _$renderer_ = this;
        _onDoneCallback = onDoneCallback;
        _onErrorCallback = onErrorCallback;
        if (Worker.isSupported) {
            var swfAssessment:Object;
            if (!((swfAssessment = _assesValidSwf(workerSrc)) is Error)) {
                _workerSrc = workerSrc;
                _workerUid = Strings.UUID;
                _canOperate = true;
            } else {
                // Exit if given worker source is invalid.
                _canOperate = false;
                _errorDetail = Strings.sprintf(BAD_WORKER, (swfAssessment as Error).message);
                onErrorCallback(_$renderer_);
            }
        } else {
            // Exit if concurrency is not supported on current platform.
            _canOperate = false;
            _errorDetail = NO_SUPPORT;
            onErrorCallback(_$renderer_);
        }
    }

    /**
     * The last recorded error detail if applicable; `null` otherwise.
     */
    public function get errorDetail():Object {
        return _errorDetail;
    }

    /**
     * Whether current platform allows concurrency, and thus operation of this class.
     */
    public function get canOperate():Boolean {
        return _canOperate;
    }

    /**
     * Convenience method to retrieve the last (slice of) organized audio map/MIDI that was sent for rendering.
     */
    public function get tracks ():Array {
        return _tracksValue;
    }

    /**
     * Holds the (audio storage) byte position that was in effect before parallel rendering started.
     * NOTE: this value is used only externally, by the logic that calculates the rendering speed. It is not used
     * by the AudioParallelRenderer instance itself.
     */
    public var positionBeforeRendering:int = -1;

    /**
     * Holds the local time (in milliseconds) that was recorded before parallel rendering started.
     * NOTE: this value is used only externally, by the logic that calculates the rendering speed. It is not used
     * by the AudioParallelRenderer instance itself.
     */
    public var timeBeforeRendering:Number;

    /**
     * Gives this AudioParallelRenderer instance something (else) to work on. A renderer can be "reused" by completely
     * changing its assignment after its initial task completed, thus saving CPU time (because destroying and creating
     * background workers/threads is a CPU-consuming operation).
     *
     * @param   tracks
     *          The (slice of) organized audio map/MIDI that is to be rendered into audio; (see
     *          SynthProxy.preRenderAudio() for details).
     *
     * @param   audioStorage
     *          Optional in subsequent calls. The storage where the rendered audio is to be deposited. If not given, the
     *          last known storage will be used.
     *
     *          NOTE: this method DOES NOT empty the storage before passing it to the renderer, and the renderer
     *          doesn't either; moreover, it WILL MIX newly rendered content with any audio that is found in the
     *          storage, for as long as the `sessionId` does not change.
     *
     * @param   sessionId
     *          Optional in subsequent calls. . The rendering session id to send to the `SynthProxy.preRenderAudio()`
     *          method. If not given, the last known session id will be used.
     *
     * @param   soundsMap
     *          Optional in subsequent calls. The loaded sounds assignment map, as an Object with sound presets as keys
     *          (e.g., "40" points to a Violin sound) and unique identifiers for pre-shared ByteArrays as values. The
     *          ByteArrays contain the actual sound bytes (e.g., the samples for a Violin sound). If not given, the last
     *          known sounds map will be used.
     */
    public function assignWork(tracks:Array, audioStorage:ByteArray = null, sessionId:String = null,
                               soundsMap:Object = null):void {

        // Exit if no concurrency available.
        if (!_canOperate) {
            _onErrorCallback(_$renderer_);
            return;
        }

        // Store the shared ByteArray where the worker is expected to write resulting audio.
        if (audioStorage) {
            if (_renderedAudioStorage !== audioStorage) {
                _renderedAudioStorage = audioStorage;
                if (!_renderedAudioStorage.shareable) {
                    _renderedAudioStorage.shareable = true;
                }
            }
        }

        // Simply save the rest of the received arguments; they will be dealt with later.
        _soundsMapValue = soundsMap;
        _tracksValue = tracks;
        _sessionValue = sessionId;

        // Prepare a chain of async functions and execute them.
        _asyncChain = new <Function>[_doAssignWork, _doExecuteWork];
        if (!_worker) {
            _asyncChain.unshift(_doMakeWorker);
        }
        _runAsyncChain(_asyncChain);
    }

    /**
     * Causes this AudioParallelRenderer instance to be put out of service. Terminates the internal background worker
     * and explicitly releases all occupied memory.
     *
     * IMPORTANT: after calling this method, the AudioParallelRenderer instance is left in an inoperable state, and any
     * attempt to use it will result in an exception.
     */
    public function decommission():void {

        // Exit if no concurrency available.
        if (!_canOperate) {
            _onErrorCallback(_$renderer_);
            return;
        }

        if (_worker && _worker.state == WorkerState.RUNNING) {

            /**
             * Executed when the internal listener of the worker being decommissioned was removed. Continues the
             * process by removing the external listener, releasing all worker-specific shared properties, terminating
             * the worker, and setting it for garbage collection.
             * @param event
             */
            function terminateWorker(event:Event):void {
                _workerChannel.removeEventListener(Event.CHANNEL_MESSAGE, terminateWorker);

                // Releases the worker-specific shared properties
                var $set:Function = _worker.setSharedProperty;
                $set(WorkersCommon.IN_CHANNEL_PREFIX + _workerUid, null);
                $set(WorkersCommon.OUT_CHANNEL_PREFIX + _workerUid, null);
                $set(WorkersCommon.INPUT_TRACKS + _workerUid, null);
                $set(WorkersCommon.OUTPUT_BYTES + _workerUid, null);
                $set(WorkersCommon.SESSION_ID + _workerUid, null);
                _soundsMapStorage.position = 0;
                var sharedSoundsMap:Object = (_soundsMapStorage.readObject() as Object);
                var soundKey:String;
                var soundBytesUid:String;
                for (soundKey in sharedSoundsMap) {
                    soundBytesUid = (sharedSoundsMap[soundKey] as String);
                    $set(soundBytesUid, null);
                }
                $set(WorkersCommon.SOUNDS_ASSIGNMENT_MAP + _workerUid, null);

                // Terminates the worker.
                _worker.terminate();

                // Releases all pointers to the worker instance and related data, so that it can be garbage collected.
                _canOperate = false;
                _asyncChain = null;
                _errorDetail = null;
                _$renderer_ = null;
                _workerSrc = null;
                _main = null;
                _mainDomain = null;
                _worker = null;
                _workerUid = null;
                _mainChannel = null;
                _workerChannel = null;
                _tracksStorage = null;
                _tracksValue = null;
                _sessionValue = null;
                _sessionStorage = null;
                _soundsMapValue = null;
                _soundsMapStorage = null;
                _renderedAudioStorage = null;
                _onDoneCallback(_$renderer_);
                _onDoneCallback = null;
                _onErrorCallback = null;
            }

            // Removes the event listener from INSIDE the worker (the one that listens to "inbound" messages, from a
            // worker perspective). After doing this, the worker is left "deaf", i.e., unable to respond to any future
            // requests from outside.
            _workerChannel.addEventListener(Event.CHANNEL_MESSAGE, terminateWorker);
            var command:Object = {};
            command[WorkersCommon.COMMAND_NAME] = WorkersCommon.COMMAND_RELEASE_LISTENER;
            _mainChannel.send(command);
        } else {
            _errorDetail = WorkersCommon.REASON_WORKER_NOT_RUNNING;
            _onErrorCallback(_$renderer_);
        }
    }

    /**
     * Initializes, configures and starts a background Worker; reports back when done (or when an error has occurred),
     * via provided `callback`.
     *
     * @param   callBack
     *          Function to call when done, or when an error has occurred. Must accept a parameter of type Object.
     *          See `AudioWorker._reportCommandExecutionError()` or `AudioWorker._reportCommandSuccess()` for expected
     *          structure.
     */
    private function _doMakeWorker(callBack:Function):void {

        // Structure we use for packaging information to report back with, being success or failure.
        var report:Object = {};

        // One-time closure, to ensure that our worker's internal state actually changes to 'running'.
        function onWorkerStatechange(event:Event):void {
            _worker.removeEventListener(Event.WORKER_STATE, onWorkerStatechange);
            var workerState:String = _worker.state;
            if (workerState == WorkerState.RUNNING) {
                report[WorkersCommon.REPORT_NAME] = WorkersCommon.WORKER_STARTED;
                callBack(report);
            } else {
                report[WorkersCommon.REPORT_NAME] = WorkersCommon.COMMAND_EXECUTION_ERROR;
                report[WorkersCommon.COMMAND_NAME] = WorkersCommon.COMMAND_START_WORKER;
                report[WorkersCommon.EXECUTION_ERROR_MESSAGE] = Strings.sprintf(BAD_WORKER_STATE, workerState,
                        WorkerState.RUNNING);
                callBack(report);
            }
        }

        // Catch any possible errors and report them back via our callback.
        try {
            // Create the worker
            _main = Worker.current;
            _mainDomain = WorkerDomain.current;
            _worker = _mainDomain.createWorker(_workerSrc);

            // Setup communications.
            _worker.setSharedProperty(WorkersCommon.WORKER_OWN_ID, _workerUid);
            _mainChannel = _main.createMessageChannel(_worker);
            _worker.setSharedProperty(WorkersCommon.IN_CHANNEL_PREFIX + _workerUid, _mainChannel);
            _workerChannel = _worker.createMessageChannel(_main);
            _worker.setSharedProperty(WorkersCommon.OUT_CHANNEL_PREFIX + _workerUid, _workerChannel);

            // Start the worker.
            _worker.addEventListener(Event.WORKER_STATE, onWorkerStatechange);
            _worker.start();
        } catch (workerInitError:Error) {
            report[WorkersCommon.REPORT_NAME] = WorkersCommon.COMMAND_EXECUTION_ERROR;
            report[WorkersCommon.COMMAND_NAME] = WorkersCommon.COMMAND_START_WORKER;
            report[WorkersCommon.EXECUTION_ERROR_MESSAGE] = workerInitError.message;
            report[WorkersCommon.EXECUTION_ERROR_ID] = workerInitError.errorID;
            callBack(report);
        }
    }

    /**
     * Sets up the internal worker by sending it its inputs & outputs (and additional info, as needed).
     *
     * @param   callBack
     *          Function to call when done, or when an error has occurred. Must accept a parameter of type Object.
     *          See `AudioWorker._reportCommandExecutionError()` or `AudioWorker._reportCommandSuccess()` for expected
     *          structure.
     */
    private function _doAssignWork(callBack:Function):void {

        // Provide the worker with sound fonts, so that it can render (MIDI to) audio.
        //
        // The `_soundsMapValue` is an Object with numeric strings as keys, and ByteArrays as values. We set the
        // ByteArrays as shared properties, and assign them worker-dependent UIDs, which we place in a
        // "shallowSoundsMap" Object that maintains the original keys from `_soundsMapValue`. We then set the
        // `shallowSoundsMap` Object as a shared property too (inside a dedicated, shared ByteArray named
        // "_soundsMapStorage").
        if (_soundsMapValue) {
            if (!_soundsMapStorage) {
                _soundsMapStorage = new ByteArray;
                _soundsMapStorage.shareable = true;
                _worker.setSharedProperty(WorkersCommon.SOUNDS_ASSIGNMENT_MAP + _workerUid, _soundsMapStorage);
            }
            var shallowSoundsMap:Object = {};
            var soundKey:String;
            var soundBytes:ByteArray;
            var soundBytesUid:String;
            for (soundKey in _soundsMapValue) {
                soundBytesUid = (WorkersCommon.SOUND_BYTES + soundKey + _workerUid);
                soundBytes = (_soundsMapValue[soundKey] as ByteArray);
                if (!soundBytes.shareable) {
                    soundBytes.shareable = true;
                }
                _worker.setSharedProperty(soundBytesUid, soundBytes);
                shallowSoundsMap[soundKey] = soundBytesUid;
            }
            _soundsMapStorage.clear();
            _soundsMapStorage.writeObject(shallowSoundsMap);
        }

        // Provide the worker with (MIDI) input, so that it has something to render into audio format.
        if (_tracksValue) {
            if (!_tracksStorage) {
                _tracksStorage = new ByteArray;
                _tracksStorage.shareable = true;
                _worker.setSharedProperty(WorkersCommon.INPUT_TRACKS + _workerUid, _tracksStorage);
            }
            _tracksStorage.clear();
            _tracksStorage.writeObject(_tracksValue);
        }

        // Provide the worker with a rendering session to use for streaming purposes
        // (see SynthProxy.preRenderAudio() for details).
        if (_sessionValue) {
            if (!_sessionStorage) {
                _sessionStorage = new ByteArray;
                _sessionStorage.shareable = true;
                _worker.setSharedProperty(WorkersCommon.SESSION_ID + _workerUid, _sessionStorage);
            }
            _sessionStorage.clear();
            _sessionStorage.writeUTFBytes(_sessionValue);
        }

        // Provide the worker with a place where to store its output.
        _worker.setSharedProperty(WorkersCommon.OUTPUT_BYTES + _workerUid, _renderedAudioStorage);

        // Use a one-time closure to verify whether our worker successfully accepted the new assignment. The closure
        // simply forwards the worker's response to our `callback`.
        function onWorkerMessage(event:Event):void {
            _workerChannel.removeEventListener(Event.CHANNEL_MESSAGE, onWorkerMessage);
            var report:Object = _workerChannel.receive();
            callBack(report);
        }

        _workerChannel.addEventListener(Event.CHANNEL_MESSAGE, onWorkerMessage);

        // Tell the worker to re-read the updated values of all configuration-related shared properties.
        var command:Object = {};
        command[WorkersCommon.COMMAND_NAME] = WorkersCommon.COMMAND_SETUP_WORKER;
        _mainChannel.send(command);
    }

    /**
     * Orders the internal background worker to begin rendering audio.
     *
     * @param   callBack
     *          Function to call when done, or when an error has occurred. Must accept a parameter of type Object.
     *          See `AudioWorker._reportCommandExecutionError()` or `AudioWorker._reportCommandSuccess()` for expected
     *          structure.
     */
    private function _doExecuteWork(callBack:Function):void {

        // Use a one-time closure to verify whether our worker successfully accepted the new assignment. The closure
        // simply forwards the worker's response to our `callback`.
        function onWorkerMessage(event:Event):void {
            _workerChannel.removeEventListener(Event.CHANNEL_MESSAGE, onWorkerMessage);
            var report:Object = _workerChannel.receive();
            callBack(report);
        }

        _workerChannel.addEventListener(Event.CHANNEL_MESSAGE, onWorkerMessage);

        var command:Object = {};
        command[WorkersCommon.COMMAND_NAME] = WorkersCommon.COMMAND_EXECUTE_WORKER;
        _mainChannel.send(command);
    }

    /**
     * Asynchronously calls, in succession, a number of internal, asynchronous functions, provided that none of them
     * reports an error (in which case, the class-level `onErrorCallback()` callback is invoked. When the chain is
     * empty, the class-level `onErrorCallback()` callback is invoked. Both class-level callback are invoked with a
     * single argument, the current AudioParallelRenderer instance. Details about the last recorded error, if should
     * be the case, can be obtained via the public `errorDetail` getter.
     */
    private function _runAsyncChain(chain:Vector.<Function>):void {

        // Obtain and run the next async function in chain, if available.
        var funcToRun:Function = (chain.shift() || null);
        if (funcToRun != null) {

            // Callback to pass to all async function in the chain. If any of the chained functions errors, this
            // will break the chain execution (and overall failure will be reported).
            var callbackFunc:Function = function (response:Object):void {

                if (_indicatesFailure(response)) {
                    _errorDetail = response;
                    _onErrorCallback(_$renderer_);
                } else {
                    _runAsyncChain(chain);
                }
            }
            funcToRun.call(this, callbackFunc);
            callbackFunc = null;
            funcToRun = null;
        } else {

            // If the chain is empty, report overall success.
            _onDoneCallback(_$renderer_);
        }
    }

    /**
     * Establishes whether given `response` is an indicative of failure, based on a list of known error formats and
     * tokens.
     * @return  `True` is given `response` seems to indicate failure, `false` otherwise.
     */
    private function _indicatesFailure(response:Object):Boolean {
        if (response && (WorkersCommon.REPORT_NAME in response)) {
            var reportName:String = (response[WorkersCommon.REPORT_NAME] as String);
            if (Strings.isAny(reportName,
                    WorkersCommon.REPORT_COMMAND_REJECTED,
                    WorkersCommon.COMMAND_EXECUTION_ERROR)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Validates given `sourceBytes` ByteArray as a potentially valid SWF source for a background Worker. Currently
     * only looks for ByteArray size and SWF header signature.
     *
     * @return  `Null` if given `sourceBytes` passes validation, or an Error instance with details otherwise.
     */
    private function _assesValidSwf(sourceBytes:ByteArray):Object {
        if (!sourceBytes || sourceBytes.length == 0) {
            return new Error(EMPTY_WORKER_SOURCE);
        }
        sourceBytes.position = 0;
        var signature:String = Strings.trim(sourceBytes.readUTFBytes(SWF_SIGNATURE_SIZE) as String);
        if (!Strings.isAny(signature, CWS_SWF_SIGNATURE, FWS_SWF_SIGNATURE)) {
            return new Error(MISSING_SWF_SIGNATURE);
        }
        return null;
    }
}
}
