package eu.claudius.iacob.synth.utils {

import eu.claudius.iacob.synth.sound.generation.SynthProxy;

import flash.display.Sprite;
import flash.events.Event;
import flash.system.MessageChannel;
import flash.system.Worker;
import flash.system.WorkerState;
import flash.utils.ByteArray;
import flash.utils.Endian;

public class AudioWorker extends Sprite {

    // Helpers
    private var _getProperty:Function;
    private var _outChannel:MessageChannel;
    private var _inChannel:MessageChannel;
    private var _ownId:String;

    // Shareable ByteArray connectors to hold required I/O data.
    private var _outputBytes:ByteArray;

    // Actual input data to use.
    private var _tracksSlice:Array;
    private var _session:String;

    // Internal logic variables.
    private var _proxy:SynthProxy;
    private var _renderingInProgress:Boolean;
    private var _setupReady:Boolean;
    private var _soundsCache:Object;
    private var _thisWorker:Worker;
    private var _auditMessages:Array;

    /**
     * Reusable Worker definition that can be externally initialized, configured and run.
     *
     * Its purpose is to render a provided chunk of organized audio map (a "tracks slice") into a provided (shared)
     * ByteArray, and signal out when cone via a specific MessageChannel. The calling code can then decide to assign it
     * a new task or decommission it.
     *
     * More than one Worker can be rendering audio at the same time, provided that the calling code properly sets them
     * up, so that no conflicts occur.
     *
     * Using Workers in the way described above enables "streaming" the audio, i.e., converting the organized audio map
     * into audio while the audio is playing (technically, with a certain lag, because a buffer is used). This is much
     * more acceptable than waiting for the entire audio to render before being able to start playback.
     */
    public function AudioWorker() {

        // Initialize helpers and communications
        _thisWorker = Worker.current;
        _getProperty = _thisWorker.getSharedProperty;
        _ownId = (_getProperty(WorkersCommon.WORKER_OWN_ID) as String);
        _outChannel = (_getProperty(WorkersCommon.OUT_CHANNEL_PREFIX + _ownId) as MessageChannel);
        _inChannel = (_getProperty(WorkersCommon.IN_CHANNEL_PREFIX + _ownId) as MessageChannel);
        _inChannel.addEventListener(Event.CHANNEL_MESSAGE, _onMessageReceived);
    }

    /**
     * Executed when a message is received via the "inbound" communication channel. It is expected that all inbound
     * communication consist in AMF serialized Objects that contain the "name" and "payload" for executing a command.
     * @param event
     */
    private function _onMessageReceived(event:Event):void {
        var command:Object = (_inChannel.receive() as Object);
        _executeCommand(command[WorkersCommon.COMMAND_NAME], command[WorkersCommon.COMMAND_PAYLOAD]);
    }

    /**
     * Re-creates an identical copy of the sounds cache, based on sent assignments map and shared BytesArrays.
     *
     * @return  Returns `true` if retrieved data structure seems about right; returns false otherwise (assignment
     *          map is missing, or empty, or malformed, or at least one sound byte address does not correctly resolve to
     *          a non-empty ByteArray).
     */
    private function _retrieveSharedSounds():Boolean {
        _soundsCache = {};
        var assignmentMapBytes:ByteArray = (_getProperty(WorkersCommon.SOUNDS_ASSIGNMENT_MAP + _ownId) as ByteArray);
        if (!assignmentMapBytes || assignmentMapBytes.length == 0) {
            return false;
        }
        assignmentMapBytes.position = 0;
        var soundsAssignmentMap:Object = (assignmentMapBytes.readObject() as Object);
        var hasKeys:Boolean = false;
        var key:String;
        var bytesAddress:String;
        var soundBytes:ByteArray;
        for (key in soundsAssignmentMap) {
            hasKeys = true;
            bytesAddress = (soundsAssignmentMap[key] as String);
            soundBytes = (_getProperty(bytesAddress) as ByteArray);
            if (!soundBytes || soundBytes.length == 0) {
                return false;
            }
            _soundsCache[key] = soundBytes;
        }
        return hasKeys;
    }

    /**
     * Executes one of a subset of known commands, based on the received info. Handles calling and execution errors, and
     * reports back via the outbound communication channel, to report success or failure.
     * @param   name
     *          The name of the command to be run.
     *
     * @param   details
     *          Optional. Additional info that might be needed for running the command.
     */
    private function _executeCommand(name:String, details:Object = null):void {

        // Special case: this command asks that the very listener that makes executing commands possible be removed.
        // This is only requested when the worker is about to be terminated, so that no unreleased memory is left
        // behind.
        if (name == WorkersCommon.COMMAND_RELEASE_LISTENER) {
            _inChannel.removeEventListener(Event.CHANNEL_MESSAGE, _onMessageReceived);
            _reportCommandSuccess(name, details);
            return;
        }

        // Regular cases: commands for setting up and executing the worker.
        if (_thisWorker.state != WorkerState.RUNNING) {
            _reportCommandRejected(name, details, WorkersCommon.REASON_WORKER_NOT_RUNNING);
            return;
        }
        switch (name) {

                // "Setup" the worker, that is, give it its input tracks, output storage, session name, and the sounds
                // to work with. An worker can be "reused" by completely changing its assignment after it has done
                // executing its current assignment (thus saving CPU time, because destroying and creating workers is a
                // time-consuming process).
            case WorkersCommon.COMMAND_SETUP_WORKER:
                if (_renderingInProgress) {
                    _reportCommandRejected(name, details, WorkersCommon.REASON_RENDERING_IN_PROGRESS);
                    break;
                }
                try {
                    _auditMessages = [];
                    _setupReady = _setup();
                    if (!_setupReady) {
                        _reportCommandExecutionError(name, details, new Error(WorkersCommon.ERROR_BAD_WORKER_SETUP));
                        break;
                    }
                    _reportCommandSuccess(name, details);
                } catch (setupError:Error) {
                    _reportCommandExecutionError(name, details, setupError);
                }
                break;

                // "Execute" the worker, that is, tell it to render audio out of given input tracks, and into given
                // output storage.
            case WorkersCommon.COMMAND_EXECUTE_WORKER :
                if (_renderingInProgress) {
                    _reportCommandRejected(name, details, WorkersCommon.REASON_RENDERING_IN_PROGRESS);
                    break;
                }
                if (!_setupReady) {
                    _reportCommandRejected(name, details, WorkersCommon.ERROR_BAD_WORKER_SETUP);
                    break;
                }
                try {
                    _auditMessages = [];
                    _render(_tracksSlice, _session);
                    _reportCommandSuccess(name, details);
                } catch (renderError:Error) {
                    _reportCommandExecutionError(name, details, renderError);
                }
                break;
        }
    }

    /**
     * Reports back failure to start executing a specific command, along with useful information.
     *
     * @param   name
     *          Rejected command's name.
     *
     * @param   details
     *          Rejected command's payload, if originally provided.
     *
     * @param   reason
     *          The reason for rejection.
     */
    private function _reportCommandRejected(name:String, details:Object, reason:String):void {
        var note:Object = {};
        note[WorkersCommon.REPORT_NAME] = WorkersCommon.REPORT_COMMAND_REJECTED;
        note[WorkersCommon.COMMAND_NAME] = name;
        if (details) {
            note[WorkersCommon.COMMAND_PAYLOAD] = details;
        }
        note[WorkersCommon.REJECTION_REASON] = reason;
        note[WorkersCommon.WORKER_OWN_ID] = _ownId;
        _outChannel.send(note);
    }

    /**
     * Reports back an error occurred while executing a specific command, along with useful information.
     *
     * @param   name
     *          Name of the command that caused an error while running.
     *
     * @param   details
     *          Payload of the command, if originally provided.
     *
     * @param   error
     *          The Error object raised while executing the command.
     */
    private function _reportCommandExecutionError(name:String, details:Object, error:Error):void {
        var note:Object = {};
        note[WorkersCommon.REPORT_NAME] = WorkersCommon.COMMAND_EXECUTION_ERROR;
        note[WorkersCommon.COMMAND_NAME] = name;
        if (details) {
            note[WorkersCommon.COMMAND_PAYLOAD] = details;
        }
        note[WorkersCommon.EXECUTION_ERROR_ID] = error.errorID;
        note[WorkersCommon.EXECUTION_ERROR_MESSAGE] = error.message +
                (_auditMessages ? '\n' + _auditMessages.join('\n') : '');
        note[WorkersCommon.WORKER_OWN_ID] = _ownId;
        _outChannel.send(note);
    }

    /**
     * Reports back that a command was successfully executed.
     *
     * @param   name
     *          The name of the successful command.
     *
     * @param   details
     *          Payload of the command, if originally provided.
     */
    private function _reportCommandSuccess(name:String, details:Object):void {
        var note:Object = {};
        note[WorkersCommon.REPORT_NAME] = WorkersCommon.COMMAND_DONE;
        note[WorkersCommon.COMMAND_NAME] = name;
        if (details) {
            note[WorkersCommon.COMMAND_PAYLOAD] = details;
        }
        note[WorkersCommon.WORKER_OWN_ID] = _ownId;
        _outChannel.send(note);
    }

    /**
     * Sets everything up for actually running the "preRenderAudio()" method o the SynthProxy class, namely the shared
     * sounds, the chunk of organized audio map to render (the "input"), the target shared ByteArray to write to (the
     * "target"), and a session id to use, in case this Worker is to be writing several times to the same ByteArray
     * (because, in this case, not providing the same session id every time would override the older writings instead
     * of merging them).
     *
     * @return  Returns `true` if input, output ans session id seem about right, and rendering audio can be attempted;
     *          return `false` otherwise (e.g., if there is nothing to be rendered because the input is empty).
     */
    private function _setup():Boolean {
        var $$:Function = _auditMessages.push;

        $$('Retrieving shared sounds...');
        var soundsRetrieved:Boolean = _retrieveSharedSounds();
        $$('Done.');

        $$('Retrieving input bytes...');
        var inputBytes:ByteArray = (_getProperty(WorkersCommon.INPUT_TRACKS + _ownId) as ByteArray);
        $$('Done.');

        if (inputBytes && inputBytes.length) {
            $$('inputBytes.length:', inputBytes.length);
            inputBytes.position = 0;

            $$('Reading tracks slice...');
            _tracksSlice = (inputBytes.readObject() as Array);
            $$('Done.');
        }
        var mustRecreateProxy:Boolean = false;

        $$('Retrieving session bytes...');
        var sessionBytes:ByteArray = (_getProperty(WorkersCommon.SESSION_ID + _ownId) as ByteArray);
        $$('Done.');

        if (sessionBytes && sessionBytes.length) {
            $$ ('sessionBytes.length:', sessionBytes.length);
            sessionBytes.position = 0;
            var session:String = sessionBytes.readUTFBytes(sessionBytes.length);
            $$ ('session:', session);
            if (_session != session) {
                _session = session;
                mustRecreateProxy = true;
            }
        }

        // Note: audio storage requires LITTLE ENDIANNESS, but this is lost in transition, i.e., despite the fact that
        // the AudioParallelRenderer class shares a ByteArray with the correct `endian` type, when picked up from inside
        // the AudioWorker class, the `endian` property of that Array reads "bigEndian". So we manually reinforce it
        // here.
        $$('Retrieving _outputBytes...');
        _outputBytes = _getProperty(WorkersCommon.OUTPUT_BYTES + _ownId) as ByteArray;
        $$('Done.');

        _outputBytes.endian = Endian.LITTLE_ENDIAN;
        if (_proxy == null || mustRecreateProxy) {
            _proxy = new SynthProxy(_outputBytes);
        }
        return (soundsRetrieved && _tracksSlice && (_tracksSlice.length > 0) && _session && _outputBytes);
    }

    /**
     * Actually renders given input "tracks" into given output "audioStorage". Sets a blocking flag during the process
     * and reports back when do via the outbound communication channel.
     *
     * @see SynthProxy.preRenderAudio()
     */
    private function _render(tracks:Array, sessionId:String):void {
        _renderingInProgress = true;
        _proxy.preRenderAudio(_soundsCache, tracks, false, sessionId);
        _renderingInProgress = false;
    }
}
}