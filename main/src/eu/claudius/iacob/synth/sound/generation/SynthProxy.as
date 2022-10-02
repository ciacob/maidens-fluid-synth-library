package eu.claudius.iacob.synth.sound.generation {
import cmodule.fluidsynth_swc.CLibInit;

import eu.claudius.iacob.synth.constants.OperationTypes;
import eu.claudius.iacob.synth.constants.PayloadKeys;
import eu.claudius.iacob.synth.constants.SamplesRenderingModes;
import eu.claudius.iacob.synth.constants.SamplesRenderingScope;
import eu.claudius.iacob.synth.constants.SeekScope;
import eu.claudius.iacob.synth.constants.SynthCommon;
import eu.claudius.iacob.synth.events.PlaybackAnnotationEvent;
import eu.claudius.iacob.synth.events.PlaybackPositionEvent;
import eu.claudius.iacob.synth.sound.map.AnnotationAction;
import eu.claudius.iacob.synth.sound.map.AnnotationTask;
import eu.claudius.iacob.synth.utils.AudioUtils;

import flash.events.Event;
import flash.events.EventDispatcher;
import flash.events.SampleDataEvent;
import flash.events.TimerEvent;
import flash.media.Sound;
import flash.media.SoundChannel;
import flash.utils.ByteArray;
import flash.utils.Timer;

public class SynthProxy extends EventDispatcher {

    private static const GENERIC_SOUND_FONT_NAME:String = './example.sf2';
    private static const SOUND_FONT_DEFAULT_BANK_NUMBER:int = 0;
    private static const SOUND_FONT_DEFAULT_PRESET_NUMBER:int = 0;
    private static const DEFAULT_SAMPLE_RATE:Number = 44100;
    private static const SAMPLE_STORAGE_FORMAT:String = 'float';
    private static const PLAYBACK_OBJECTS_OFFSET:Number = -200;
    private static const SILENCE_THRESHOLD:Number = 0.001;
    private static const SCORE_ITEM_ANNOTATION_WINDOW:int = 100;
    private static const CHANNEL_POLL_INTERVAL:int = 1;
    private static const STARTING_PLAYBACK_POSITION:int = 1;
    private static const SAMPLES_CHUNK_SIZE:uint = 8192;

    private var _channelObserverClosure:Function;
    private var _synthShell:CLibInit;
    private var _synth:Object
    private var _currPreset:int = -1;
    private var _audioStorage:ByteArray;
    private var _cachedAudioLength:uint;
    private var _audioChanged:Boolean;
    private var _preRenderedSound:Sound = null;
    private var _preRenderedChannel:SoundChannel;
    private var _streamedSound:Sound = null;
    private var _streamedChannel:SoundChannel = null;
    private var _channelObserverTimer:Timer;
    private var _annotationTasks:Array;
    private var _noteStorages:Object;
    private var _soundsCache:Object;
    private var _prerenderedPlaybackInProgress:Boolean;
    private var _streamedPlaybackInProgress:Boolean;
    private var _lastPlaybackPosition:Number = STARTING_PLAYBACK_POSITION;
    private var _sessionId:String;
    private var _streamingPositionOffset : Number = 0;


    /**
     * Main class that handles converting an organized sound map (produced via a Timeline instance) into audio data
     * that is ready to be fed into a sound interface.
     *
     * @param   audioStorage
     *          A "little endian" ByteArray to store the rendered audio in.
     *
     *          NOTES:
     *          (1) You can use `AudioUtils.makeSamplesStorage()` to produce a ByteArray that is suitable to pass to the
     *          `audioStorage` parameter.
     *
     *          (2) You can use the SynthProxy class as a player, initializing the class with a ByteArray instance you
     *          can write to; call `invalidateAudioCache()` and then `playBackPrerenderedAudio()`, and you should be
     *          able to hear your audio, even if it was ENTIRELY externally produced.
     *
     * @constructor
     */
    public function SynthProxy(audioStorage:ByteArray) {
        _synthShell = new CLibInit;
        _annotationTasks = [];
        _noteStorages = {};
        _audioStorage = audioStorage;
    }

    /**
     * Convenience method for accessing the audio storage ByteArray this class was instantiated with.
     */
    public function get audioStorage():ByteArray {
        return _audioStorage;
    }

    /**
     * Returns the currently stored total length, in milliseconds, of the audio that has been cached so far. To
     * get the most up to date value, call `computeCachedAudioLength()` before reading this value.
     */
    public function get cachedAudioLength():uint {
        return _cachedAudioLength;
    }

    /**
     * Renders offline the music described in the given `tracks` and returns the resulting samples inside of a
     * ByteArray. This samples can be fed into the system's default sound interface via the `data` property of the
     * SampleDataEvent dispatched by a playing Sound object (see documentation on flash.media.Sound for details).
     *
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
     *          the synthesizer must execute.
     *
     * @param   normalizePeak
     *          Optional, default false. Normalizes the values of the samples returned by the synth,
     *          so that the highest value is closest to `1.0`. Also ensures that no clipping occurs.
     *
     * @param   sessionId
     *          Optional. If given, will not clear the audio previously rendered in same-id sessions. Enables streaming
     *          a large map of "tracks", by "slicing" it in smaller chunks, and rendering the slices just in time, while
     *          playing them back.
     *
     * @return  Returns the same instance of the ByteArray that is internally stored, and that will be used for
     *          playback; this gives the client code a chance to modify the prerendered audio material before playing it
     *          back (e.g., to add reverb, work on the EQ or dynamics, etc.).
     */
    public function preRenderAudio(sounds:Object, tracks:Array, normalizePeak:Boolean = false,
                                   sessionId:String = null):void {
        _soundsCache = sounds;
        var mustReset:Boolean = (!sessionId || sessionId != _sessionId);
        _sessionId = sessionId;

        // Prepare/reset storages.; rewind playback position if needed
        if (mustReset) {
            _audioStorage.clear();
            if (_lastPlaybackPosition != STARTING_PLAYBACK_POSITION) {
                _audioStorage.position = 0;
                _lastPlaybackPosition = STARTING_PLAYBACK_POSITION;
                dispatchEvent(new PlaybackPositionEvent(0, 0));
            }
        }

        // Buffer the tracks; normalize resulting audio if requested.
        _renderTracks(tracks, _audioStorage);
        if (normalizePeak) {
            AudioUtils.normalizeValues (_audioStorage);
        }

        // Raise a flag, so that we know to upload the newly rendered audio into our Sound object.
        _audioChanged = true;
    }

    /**
     * Plays back the audio. Use this once the audio was fully prerendered, and it expects no further changes/additions.
     */
    public function playBackPrerenderedAudio():void {
        if (!_audioStorage) {
            return;
        }
        if (_prerenderedPlaybackInProgress) {
            return;
        }
        if (_streamedPlaybackInProgress) {
            _doStopStreamedPlayback();
        }
        _prerenderedPlaybackInProgress = true;
        if (!_preRenderedSound) {
            _preRenderedSound = new Sound();
        }
        if (_audioChanged) {
            var numSamples:uint = (_audioStorage.length / SynthCommon.SAMPLE_BYTE_SIZE);
            _audioStorage.position = 0;
            _preRenderedSound.loadPCMFromByteArray(_audioStorage, numSamples, SAMPLE_STORAGE_FORMAT, false, DEFAULT_SAMPLE_RATE);
            _audioChanged = false;
        }
        _preRenderedChannel = _preRenderedSound.play(_lastPlaybackPosition);
        if (_preRenderedChannel) {
            _preRenderedChannel.addEventListener(Event.SOUND_COMPLETE, _onPrerenderedSoundComplete);
            _startPlaybackObserver(_preRenderedChannel);
        } else {

            // NOTE: starting playback a couple milliseconds before the end of the audio can result in the sound engine
            // refusing to play and returning a `null` SoundChannel. We recover from this situation by doing a
            // canonical stop, so that the next call to "playback..." will be legit.
            stopPrerenderedPlayback(true);
        }
    }

    /**
     * Plays back the audio. Use this while the audio is still being rendered, and it is expected to undergo changes as
     * tracks/voices are added to the mix.
     */
    public function playBackStreamedAudio():void {
        if (!_audioStorage) {
            return;
        }
        if (_streamedPlaybackInProgress) {
            return;
        }
        if (_prerenderedPlaybackInProgress) {
            stopPrerenderedPlayback(true);
        }
        _streamedPlaybackInProgress = true;

        // Recreate the Sound object dedicated to streaming, or else its SoundChannel `position` will not reset to `0`.
        if (_streamedSound) {
            _streamedSound.removeEventListener(SampleDataEvent.SAMPLE_DATA, _onStreamedSoundSampleRequested);
            _streamedSound = null;
        }
        _streamedSound = new Sound;
        _streamedSound.addEventListener(SampleDataEvent.SAMPLE_DATA, _onStreamedSoundSampleRequested);
        _streamedChannel = _streamedSound.play();
        if (_streamedChannel) {
            _startPlaybackObserver(_streamedChannel);
        } else {
            _doStopStreamedPlayback();
        }
    }

    /**
     * Interrupts playback of the prerendered audio if it is in progress, optionally "rewinding" it, i.e., seeking
     * back to the start of the recording.
     *
     * @param   rewind
     *          Optional, default "false"; whether to seek out to the beginning of the recording after stopping its
     *          playback. If "false", next playback session will resume from the point it was previously stopped at.
     *          NOTE: when end of audio is encountered, a rewind action is automatically carried on.
     */
    public function stopPrerenderedPlayback(rewind:Boolean = false):void {
        if (!_audioStorage) {
            return;
        }
        if (!_prerenderedPlaybackInProgress) {
            return;
        }
        if (!_preRenderedChannel) {
            return;
        }
        _lastPlaybackPosition = _preRenderedChannel.position;
        _preRenderedChannel.stop();
        if (rewind) {
            _audioStorage.position = 0;
            _lastPlaybackPosition = STARTING_PLAYBACK_POSITION;
            dispatchEvent(new PlaybackPositionEvent(0, 0));
        }
        _stopPlaybackObserver();
        _resetAnnotationTasks();
        _prerenderedPlaybackInProgress = false;
    }

    /**
     * Interrupts playback of the streamed audio.
     *
     * @param   rewind
     *          Optional, default "false"; whether to seek out to the beginning of the recording after stopping its
     *          playback. If "false", next playback session will resume from the point it was previously stopped at.
     *          NOTE: when end of audio is encountered, a rewind action is automatically carried on.
     *
     * NOTE: you must call `stopStreamedPlayback(true)` in order to be able to call `playBackStreamedAudio()` a second
     * time. That is because when streaming there is no clear signal of a stream end, and unless explicitly stopped,
     * playing back streamed audio will go on forever. The `StreamingUtils` class (which is the main client of the
     * `playBackStreamedAudio` and `stopStreamedPlayback` functions) works this around by observing the `position`
     * reported by the playing SoundChannel, and triggering a `stopStreamedPlayback(true)` when it receives the same
     * `position` four times in a row.
     */
    public function stopStreamedPlayback(rewind:Boolean = false):void {
        _doStopStreamedPlayback(rewind);
    }

    /**
     * Flags the internal audio storage as having been changed externally.
     *
     * NOTE:
     * You MUST call this method after externally changing the ByteArray returned by `preRenderAudio()`, or your changes
     * will NOT be heard. Tha is because the `playBackPrerenderedAudio` method actually plays from a cache, and that
     * cache is only updated when marked as invalid (the `preRenderAudio` method automatically does that).
     */
    public function invalidateAudioCache():void {
        _audioChanged = true;
    }

    /**
     * Computes the length, in milliseconds, of the audio that has been rendered so far, and stores the result
     * internally. To access the result, use the `cachedAudioLength` getter.
     */
    public function computeCachedAudioLength():void {
        _computeCachedAudioLength();
    }

    /**
     * Actually stops streamed playback.
     *
     * @param   rewind
     *          Optional, default "false"; whether to seek out to the beginning of the recording after stopping its
     *          playback. If "false", next playback session will resume from the point it was previously stopped at.
     *          NOTE: when end of audio is encountered, a rewind action is automatically carried on.
     */
    private function _doStopStreamedPlayback(rewind : Boolean = false):void {
        if (!_audioStorage) {
            return;
        }
        if (!_streamedPlaybackInProgress) {
            return;
        }
        if (!_streamedChannel) {
            return;
        }
        _streamedChannel.stop();
        _stopPlaybackObserver();
        _resetAnnotationTasks();
        _streamedPlaybackInProgress = false;
        if (rewind) {
            _streamingPositionOffset = 0;
            _audioStorage.position = 0;
            _lastPlaybackPosition = STARTING_PLAYBACK_POSITION;
            dispatchEvent(new PlaybackPositionEvent(0, 0));
        } else {
            _streamingPositionOffset += _streamedChannel.position;
        }
    }

    /**
     * Wrapper around synth's "noteOn" function.
     *
     * @param   preset
     *          The MIDI instrument (i.e., timbre definition) to use when producing this note. This deviates from the
     *          MIDI standard, which stipulates that a NOTE_ON message must receive a pitch, velocity and CHANNEL
     *          instead.
     *
     * @param   key
     *          Musical pitch to produce, in MIDI pitch notation. "Middle C" is 60; integer, 0 to 126.
     *
     * @param   velocity
     *          Individual sample amplification; integer,  0 to  126, where "0" is virtually silent, and
     *          "126" is loudest.
     *
     * NOTE: our synth only uses the first MIDI channel. We create a synth instance for every preset (i.e., MIDI
     * instrument type), and mix their audio output offline, so practically we can use infinite channels (as opposed to
     * the MIDI specification, which only accepts 16).
     */
    private function _noteOn(preset:int, key:int, velocity:int = 64):void {
        _configureSynthFor(preset);
        _synth.fluidsynth_noteon(0, key, velocity);
    }

    /**
     * Wrapper around synth's "noteOff" function.
     *
     * @param   preset
     *          The MIDI instrument (i.e., timbre definition) to use when producing this note. This deviates from the
     *          MIDI standard, which stipulates that a NOTE_OFF message must receive a pitch and a CHANNEL.
     *          instead.
     *
     * @param   key
     *          The musical pitch of the playing note that is to be stopped.
     *
     * @see noteOn
     */
    private function _noteOff(preset:int, key:int):void {
        _configureSynthFor(preset);
        _synth.fluidsynth_noteoff(0, key);
    }

    /**
     * Executed in response to the Sound object dedicated to prerendered audio running out of samples to play (aka,
     * end of the pre-rendered material is encountered).
     *
     * @param   event
     *          The "SOUND_COMPLETE" event dispatched by the playing Sound object (see documentation on
     *          flash.media.Sound for details).
     */
    private function _onPrerenderedSoundComplete(event:Event):void {
        stopPrerenderedPlayback(true);
    }

    /**
     * Fired at regular intervals by the Sound object responsible with "streamed" playback, i.e., playing beck the
     * rendered sound while it is rendered.
     *
     * @param   event
     *          A SampleDataEvent instance to be used as a vehicle for feeding sound samples into the audio interface.
     */
    private function _onStreamedSoundSampleRequested(event:SampleDataEvent):void {
        var numSentSamples:uint = 0;
        var sampleValue:Number;
        var eventData:ByteArray = event.data;
        var hasAtLeastOneSample:Boolean;
        while (numSentSamples < SAMPLES_CHUNK_SIZE) {
            numSentSamples++;
            hasAtLeastOneSample = (audioStorage.bytesAvailable >= SynthCommon.SAMPLE_BYTE_SIZE);
            if (hasAtLeastOneSample) {
                sampleValue = _audioStorage.readFloat();

                // Writing it twice for left and right channel, respectively; for the time being, we only provide
                // mono signal.
                eventData.writeFloat(sampleValue);
                eventData.writeFloat(sampleValue);
            }
        }
    }

    /**
     * Sets up a Timer that continuously checks for the current playback position, and triggers all annotations that are
     * within a reasonable range (between the last and current time cue, to be precise). For each annotation found, a
     * PlaybackAnnotationEvent is dispatched, containing the relevant AnnotationTask instance and the time (in
     * milliseconds) it was triggered at.
     */
    private function _startPlaybackObserver(channel:SoundChannel):void {
        if (channel && !_channelObserverTimer) {

            // Store the last position we read from in an external context, to prevent the `_channelObserverClosure()`
            // closure from caching it.
            var $:Object = {
                "prevTimeCue": 0 + (_streamedPlaybackInProgress? Math.round(_streamingPositionOffset) : 0)
            };

            // Create a shared closure that triggers annotations in batches
            _channelObserverClosure = function (event:TimerEvent):void {

                // Retrieve the playback position from the currently playing channel.
                var playbackPosition:Number =  channel.position + (_streamedPlaybackInProgress?
                        _streamingPositionOffset : 0);
                var timeCue:uint = Math.round(playbackPosition);

                // Compute and dispatch a playback percent, based on the recorded time known so far.
                var playbackPercent:Number = Math.max(0,
                        Math.min(1, (playbackPosition - PLAYBACK_OBJECTS_OFFSET) / _cachedAudioLength));
                dispatchEvent(new PlaybackPositionEvent(playbackPercent, timeCue));

                // Locate and execute annotations based on current playback position.
                var i:int;
                var task:AnnotationTask;
                var tasksSlice:Array = _annotationTasks.slice($.prevTimeCue, timeCue);
                $.prevTimeCue = timeCue;
                var numFramesInSlice:int = tasksSlice.length;
                for (i = 0; i < numFramesInSlice; i++) {
                    task = (tasksSlice[i] as AnnotationTask);
                    if (task && !task.done) {
                        task.done = true;
                        dispatchEvent(new PlaybackAnnotationEvent(task));
                    }
                }
            }

            // Operate the shared closure based on an infinite Timer.
            _channelObserverTimer = new Timer(CHANNEL_POLL_INTERVAL);
            _channelObserverTimer.addEventListener(TimerEvent.TIMER, _channelObserverClosure);
            _channelObserverTimer.start();
        }
    }

    /**
     * Computes and globally stores the total length of the audio cached so far (in milliseconds).
     */
    private function _computeCachedAudioLength():void {
        if (!_audioStorage) {
            return;
        }
        var numRecordedSamples:Number = (_audioStorage.length / SynthCommon.SAMPLE_BYTE_SIZE);
        _cachedAudioLength = ((numRecordedSamples / SynthCommon.SAMPLES_PER_MSEC) | 0);  // same as Math.floor(), only faster
    }

    /**
     * Removes the (previously set) Timer that continuously checks for the current playback position, and triggers
     * annotations accordingly.
     */
    private function _stopPlaybackObserver():void {
        if (_channelObserverTimer && (_channelObserverClosure != null)) {
            _channelObserverTimer.stop();
            _channelObserverTimer.removeEventListener(TimerEvent.TIMER, _channelObserverClosure);
            _channelObserverTimer = null;
        }
    }

    /**
     * Walks all registered AnnotationTask instances and sets their "done" property to `false`, so they can
     * be triggered again.
     */
    private function _resetAnnotationTasks():void {
        var i:int;
        var numTasks:uint = _annotationTasks.length;
        var task:AnnotationTask;
        for (i = 0; i < numTasks; i++) {
            task = (_annotationTasks[i] as AnnotationTask);
            if (task) {
                task.done = false;
            }
        }
    }

    /**
     * Reroutes the shared synth instance to use the proper SoundFonts for the given `preset` (e.g., to use the
     * "Violin" sound font when given `preset` is `40`).
     *
     * @param   preset
     *          The MIDI instrument (i.e., timbre definition) the shared synthesizer must use. In this
     *          implementation, we reprogram the synthesizer instance for each new type of instrument to be used,
     *          and do an offline mixing of the resulting waveforms in order to produce a multitimbral recording.
     *          If the shared synth instance is already configured with the given `preset`, nothing happens.
     */
    private function _configureSynthFor(preset:int):void {
        if (preset == _currPreset) {
            return;
        }
        _currPreset = preset;
        var soundFonts:ByteArray = _getSoundsForPreset(preset);
        if (soundFonts) {
            _synthShell.supplyFile(GENERIC_SOUND_FONT_NAME, soundFonts);
            _synth = _synthShell.init();
            _synth.fluidsynth_init(SOUND_FONT_DEFAULT_BANK_NUMBER, SOUND_FONT_DEFAULT_PRESET_NUMBER);
        }
    }

    /**
     * Retrieves the raw content inside of a *.sf2 file that matches the provided `preset`.
     *
     * @param   preset
     *          A preset number to match the name of a *.sf2 file in the application's directory.
     *
     * @return  A ByteArray containing the bytes inside the file, or `null` if the file cannot be found.
     */
    private function _getSoundsForPreset(preset:int):ByteArray {
        return (_soundsCache[preset] as ByteArray);
    }

    /**
     * Requests samples from the synth to provide audio for the given number of
     * `milliseconds`. Received samples are stored in given `samplesStorage`.
     *
     * @param   milliseconds
     *          The time span, in milliseconds, the synth must produce audio samples for.
     *          The time-to-samples conversion is made based on the SAMPLES_PER_MSEC
     *          constant. This parameter is irrelevant when both (1) `samplesBuffer` is
     *          given, and (2) `bypassSynth` is `true`, in which case it can be sent any
     *          value (for bypass purposes). See `samplesBuffer` and `bypassSynth` for
     *          details.
     *
     * @param   samplesStorage
     *          ByteArray where samples produced by the synth are to be deposited.
     *
     * @param   $samplesBuffer
     *          Optional, use `null` to bypass. A ByteArray to be used for buffering (and
     *          possibly altering) the samples before writing them to the `samplesStorage`.
     *          Useful if you need full control over the process, or if you want to pass in
     *          pre-rendered material (see the `bypassSynth` parameter). If you don't
     *          provide a `samplesBuffer`, the method internally creates one, and discards
     *          it afterwards.
     *          NOTE: if the `synth` argument is null, then `$samplesBuffer` becomes mandatory.
     *
     * @param   synth
     *          Optional, default `null`. A synthesizer instance to use for producing the
     *          samples. If none is given, it is assumed that the samples were already
     *          produced, and are stored in the `$samplesBuffer`.
     *
     *          NOTES:
     *          1. If no `synth` is given, then the `milliseconds` parameter will be ignored.
     *          2. If the `$samplesBuffer` argument is null, then `synth` becomes mandatory.
     *
     *
     * @param   mode
     *          Optional. How to add samples to the given storage: `0` overrides everything
     *          found starting from the storage's current position (the default), while `1`
     *          mixes new material over old one, also starting from the storage's current
     *          position (it adds the numeric values of incoming samples to the values of
     *          existing samples, and replaces the original with the result). Normalizing /
     *          reducing the output is not carried out in this function.
     *
     * @param   crossfadeTime
     *          Optional, default `0`. Only of relevance if `mode` is `0` (i.e., "override").
     *          Performs a linear crossfade between incoming and existing signal over the
     *          specified amount of time, by fading out existing material toward 0%, while
     *          fading in new material toward 100%, and adding the result.
     *
     * @throws  If both `$samplesBuffer` and `synth` arguments are null at the same time.
     *
     * @see eu.claudius.iacob.synth.constants.SamplesRenderingModes.
     */
    private function _renderSamples(milliseconds:Number, samplesStorage:ByteArray,
                                    $samplesBuffer:ByteArray = null, synth:Object = null,
                                    mode:int = 0, crossfadeTime:Number = 0):void {

        if ($samplesBuffer == null && synth == null) {
            throw (new ArgumentError('Both the `$samplesBuffer` and `synth` arguments cannot be null.'));
        }

        // Create the work buffer or retrieve it from the arguments.
        var samplesBuffer:ByteArray = ($samplesBuffer || AudioUtils.makeSamplesStorage());
        if (synth != null) {

            // If we must produce samples, generate them and put them in the buffer (do not
            // directly store them).
            var dueSamples:Number = ((milliseconds * SynthCommon.SAMPLES_PER_MSEC) | 0)  // same as Math.floor(), only faster;
            var dueBytes:Number = (dueSamples * SynthCommon.SAMPLE_BYTE_SIZE);
            while (samplesBuffer.length < dueBytes) {
                synth.fluidsynth_getdata(samplesBuffer);
            }
        }

        // At this point we have the new content (either generated or passed in as an argument). We commit it based on
        // the given `mode` and `crossfadeTime`.
        var currSrcSample:Number;
        var targetPositionBeforeRead:int;
        var currTargetSample:Number;
        var inCrossFactor:Number;
        var outCrossFactor:Number;
        var crossNumSamples:Number = ((crossfadeTime * SynthCommon.SAMPLES_PER_MSEC) | 0);  // same as Math.floor(), only faster
        var crossNumBytes:Number = (crossNumSamples * SynthCommon.SAMPLE_BYTE_SIZE);
        samplesBuffer.position = 0;
        while (samplesBuffer.bytesAvailable) {

            // Get the source sample.
            currSrcSample = samplesBuffer.readFloat();

            // Get the target sample, without affecting the target storage's current position; assume `0` by default.
            currTargetSample = 0;
            targetPositionBeforeRead = samplesStorage.position;
            if (samplesStorage.bytesAvailable &&
                    samplesStorage.length - targetPositionBeforeRead >= SynthCommon.SAMPLE_BYTE_SIZE) {
                currTargetSample = samplesStorage.readFloat();
                samplesStorage.position = targetPositionBeforeRead;
            }

            // If we must override the target samples:
            if (mode == SamplesRenderingModes.OVERRIDE) {

                // Perform the crossfade if one has been requested, and while we are inside the crossfade window.
                if (crossfadeTime > 0 && samplesBuffer.position < crossNumBytes) {
                    inCrossFactor = (samplesBuffer.position / crossNumBytes);
                    outCrossFactor = (1 - inCrossFactor);
                    currSrcSample *= inCrossFactor;
                    currTargetSample *= outCrossFactor;
                    samplesStorage.writeFloat(currSrcSample + currTargetSample);
                    continue;
                }

            }

            // If we must combine source and target samples:
            else if (mode == SamplesRenderingModes.MIX) {
                samplesStorage.writeFloat(currSrcSample + currTargetSample);
                continue;
            }

            // By default, just write the current source sample into the storage, at the storage's current position.
            samplesStorage.writeFloat(currSrcSample);
        }

        // Recycle the samples buffer if one was internally created (i.e., not externally injected).
        if (!$samplesBuffer && samplesBuffer) {
            AudioUtils.recycleSamplesStorage(samplesBuffer);
        }
    }

    /**
     * Requests samples from the synth until they start peaking below the SILENCE_THRESHOLD. This method is intended
     * to be used for capturing the sound produced AFTER a "noteOff" message was issued, which, for most instruments,
     * produces the "tail", or "release" portion of their sound envelope. This method "auto-trims" the result, only
     * capturing as many samples as needed for the sound to fully decay. Produced samples are appended to existing ones.
     *
     * @param   samplesStorage
     *          ByteArray where samples produced by the synth are to be deposited.
     *
     * @param   synth
     *          A synthesizer instance to use for producing the samples.
     */
    private static function _renderTailSamples(samplesStorage:ByteArray, synth:Object):void {
        var samplesMax:Number = Number.MAX_VALUE;
        var windowStart:uint;
        do {
            windowStart = samplesStorage.position;

            // Get samples from synth for as long as they peak above the SILENCE_THRESHOLD.
            synth.fluidsynth_getdata(samplesStorage);
            samplesMax = _getSamplesMax(samplesStorage, windowStart, SAMPLES_CHUNK_SIZE);
        } while (samplesMax > SILENCE_THRESHOLD);
    }

    /**
     * Returns the maximum positive values of all the given `samples`.
     * NOTES:
     * - for speed, only positive samples are considered;
     * - leaves the internal `position` of the given `samples` ByteArray at its end.
     *
     * @param   samples
     *          ByteArray with audio samples (as 32 bit numbers) to find their max peak
     *          value.
     *
     * @param   windowStart
     *          Position, in the `samples` ByteArray, to start observing from.
     *
     * @param   windowSize
     *          Number of bytes to observe counting from `windowStart`.
     *
     * @return  A positive number greater than or equal to `0`.
     */
    private static function _getSamplesMax(samples:ByteArray, windowStart:uint, windowSize:uint):Number {
        var max:Number = 0;
        var sampleSize:int = SynthCommon.SAMPLE_BYTE_SIZE;
        samples.position = windowStart;
        var currSample:Number;
        while (windowSize > 0) {
            currSample = samples.readFloat();
            if (currSample > max) {
                max = currSample;
            }
            windowSize -= sampleSize;
        }
        return max;
    }

    /**
     * Walks given list of `flattenedTracks` (a multidimensional Array containing the low-level synth instructions
     * needed to produce sound and trigger annotations for each defined Track) and carries on the needed actions,
     * producing sound samples and compiling a list of timed annotations in the process. Resulting audio samples are
     * stored in given `samplesStorage` ByteArray and can be played back via the system's default sound interface as
     * such, using a Sound object (see documentation on flash.media.Sound for details).
     *
     * @param   flattenedTracks
     *          A multidimensional Array containing the low-level synth instructions needed to produce sound and trigger
     *          annotations for each defined Track
     *
     * @param   samplesStorage
     *          A ByteArray to hold the final, ready-to-play version of the synthesized audio.
     */
    private function _renderTracks(flattenedTracks:Array, samplesStorage:ByteArray):void {
        _clearPlaybackAnnotations();

        if (PLAYBACK_OBJECTS_OFFSET < 0) {
            _seekToStorageTime(Math.abs(PLAYBACK_OBJECTS_OFFSET), samplesStorage);
        }

        var i:int;
        var j:int;
        var numFlattenedTracks:uint = flattenedTracks.length;
        var flattenedTrack:Array;
        var numInstructions:uint;
        var instruction:Object;
        var seekScope:String;
        var seekTime:int;
        var scoreItemId:String;
        var scoreItemDuration:int;
        var scoreItemOnTime:int;
        var scoreItemOffTime:int;
        var scoreItemWindow:int;
        var notePreset:int;
        var noteKey:int;
        var noteVelocity:int;
        var renderScope:String;
        var noteId:String;
        var samplesDuration:int;
        var renderStorage:ByteArray;
        for (i = 0; i < numFlattenedTracks; i++) {
            flattenedTrack = (flattenedTracks[i] as Array);
            numInstructions = flattenedTrack.length;
            for (j = 0; j < numInstructions; j++) {
                instruction = flattenedTrack[j];
                switch (instruction[PayloadKeys.TYPE]) {
                    case OperationTypes.TYPE_HIGHLIGHT_SCORE_ITEM:
                        scoreItemId = (instruction[PayloadKeys.SCORE_ITEM_ID] as String);
                        scoreItemOnTime = (instruction[PayloadKeys.TIME] as int);
                        scoreItemDuration = (instruction[PayloadKeys.DURATION] as int);
                        scoreItemWindow = Math.min(((scoreItemDuration / 2) | 0), SCORE_ITEM_ANNOTATION_WINDOW);
                        scoreItemOffTime = (scoreItemOnTime + scoreItemDuration - scoreItemWindow);
                        var showItemAction:AnnotationAction = new AnnotationAction(
                                OperationTypes.TYPE_HIGHLIGHT_SCORE_ITEM, scoreItemId);
                        var showItemTask:AnnotationTask = new AnnotationTask(
                                new <AnnotationAction>[showItemAction]);
                        _pushAnnotationRegion(showItemTask, scoreItemOnTime, scoreItemWindow);
                        var hideItemAction:AnnotationAction = new AnnotationAction(
                                OperationTypes.TYPE_UNHIGHLIGHT_SCORE_ITEM, scoreItemId);
                        var hideItemTask:AnnotationTask = new AnnotationTask(
                                new <AnnotationAction>[hideItemAction]);
                        _pushAnnotationRegion(hideItemTask, scoreItemOffTime, scoreItemWindow);
                        break;
                    case OperationTypes.TYPE_SEEK_TO:
                        noteId = (instruction[PayloadKeys.ID] as String);
                        seekScope = (instruction[PayloadKeys.SEEK_SCOPE] as String);
                        seekTime = (instruction[PayloadKeys.TIME] as int);
                        if (seekScope == SeekScope.START_OF_NOTE_HEAD) {
                            _seekToStorageTime(seekTime, samplesStorage);
                        }
                        break;
                    case OperationTypes.TYPE_NOTE_ON:
                        noteId = (instruction[PayloadKeys.ID] as String);
                        notePreset = (instruction[PayloadKeys.PRESET] as int);
                        noteKey = (instruction[PayloadKeys.KEY] as int);
                        noteVelocity = (instruction[PayloadKeys.VELOCITY] as int);
                        _noteOn(notePreset, noteKey, noteVelocity);
                        break;
                    case OperationTypes.TYPE_REQUEST_SAMPLES:
                        noteId = (instruction[PayloadKeys.ID] as String);
                        notePreset = (instruction[PayloadKeys.PRESET] as int);
                        renderScope = (instruction[PayloadKeys.RENDER_SCOPE] as String);
                        if (renderScope == SamplesRenderingScope.RENDER_NOTE_HEAD) {
                            samplesDuration = instruction[PayloadKeys.DURATION];
                            renderStorage = _getNoteStorageFor(noteId);
                            _configureSynthFor(notePreset);
                            _renderSamples(samplesDuration, renderStorage, null, _synth);
                        } else if (renderScope == SamplesRenderingScope.RENDER_NOTE_TAIL) {
                            renderStorage = _getNoteStorageFor(noteId, false);
                            if (renderStorage) {
                                _configureSynthFor(notePreset);
                                _renderTailSamples(renderStorage, _synth);
                                _renderSamples(-1, samplesStorage, renderStorage, null, SamplesRenderingModes.MIX);
                                _discardNoteStorageFor(noteId);
                            }
                        }
                        break;
                    case OperationTypes.TYPE_NOTE_OFF:
                        noteId = (instruction[PayloadKeys.ID] as String);
                        notePreset = (instruction[PayloadKeys.PRESET] as int);
                        noteKey = (instruction[PayloadKeys.KEY] as int);
                        _noteOff(notePreset, noteKey);
                        break;
                }
            }
        }
        _sealAnnotationRegions();
    }

    /**
     * Retrieves and/or creates a dedicated samples storage to be used for putting together the sound of a specific
     * note.
     *
     * @param   noteId
     *          An unique ID to be associated with this sample storage.
     *
     * @param   autoCreate
     *          Whether to create a storage for the given `noteId` if one doesn't already exist (the default).
     *
     * @return  The retrieved or created samples storage (a ByteArray instance).
     */
    private function _getNoteStorageFor(noteId:String, autoCreate:Boolean = true):ByteArray {
        if (autoCreate) {
            if (!(noteId in _noteStorages)) {
                _noteStorages[noteId] = AudioUtils.makeSamplesStorage();
            }
        }
        var storage:Object;
        return ((storage = _noteStorages[noteId]) ? storage as ByteArray : null);
    }

    /**
     * Recycles and discards an existing note samples storage.
     * @param noteId
     */
    private function _discardNoteStorageFor(noteId:String):void {
        if (noteId in _noteStorages) {
            AudioUtils.recycleSamplesStorage(_noteStorages[noteId] as ByteArray);
            delete _noteStorages[noteId];
        }
    }

    /**
     * Moves the `position` inside the internal samples storage ByteArray to the equivalent of given `time`. Subsequent
     * sample writing operations will start from that point onward (causing existing samples to be replaced or altered,
     * subject to the value sent to the `mode` argument of the `_renderSamples` method.
     *
     * @param   time
     *          A time, in milliseconds, representing a position in the internal samples storage ByteArray. This time
     *          will be transformed to samples, which will be transformed into bytes, which will be used to set the
     *          internal pointer (aka `position`) of the ByteArray. The pointer is to be moved immediately AFTER the
     *          given `time`.
     *
     *          NOTES:
     *          1. Since the pointer is 0-based, a setting of `3` will actually cause the fourth byte in the Array to
     *          be read or written on the next read/write operation.
     *
     *          2. If the storage does not currently hold that many samples (i.e., if the given `time` represents a
     *          point that is beyond the current length of the ByteArray), the storage will be padded with "0" samples
     *          (complete silence), as needed.
     *
     * @param   samplesStorage
     *          The samples ByteArray to seek into.
     */
    private static function _seekToStorageTime(time:Number, samplesStorage:ByteArray):void {
        var numSamples:uint = ((time * SynthCommon.SAMPLES_PER_MSEC) | 0);  // same as Math.floor(), only faster
        var numBytes:Number = (numSamples * SynthCommon.SAMPLE_BYTE_SIZE);

        // Pad the storage with silent samples if needed.
        if (numBytes > samplesStorage.length) {
            samplesStorage.length = numBytes;
        }

        // Move the pointer immediately after given `time`.
        samplesStorage.position = numBytes;
    }

    /**
     * Clears all defined playback events (without also deleting the Array they were defined in).
     */
    private function _clearPlaybackAnnotations():void {
        if (_annotationTasks) {
            _annotationTasks.length = 0;
        }
    }

    /**
     * Stores an AnnotationTask instance in relation to a region in the buffered audio. A PlaybackEvent containing that
     * instance is fired on the first entrance of the playhead in the designated region.
     *
     * NOTES:
     * Due to processing overload, there will be some granularity associated to the playhead, so that not every
     * millisecond will be reported (some will be skipped). If a region is very small, the playhead might skip it
     * entirely in overload scenarios, and a PlaybackEvent for that region MIGHT NEVER FIRE.
     *
     * @param   task
     *          An AnnotationTask to associate to a region.
     *
     * @param   time
     *          Region start, in milliseconds.
     *
     * @param   duration
     *          Region length, in milliseconds.
     */
    private function _pushAnnotationRegion(task:AnnotationTask, time:Number, duration:Number):void {
        if (_audioStorage) {
            var start:Number = Math.max(0, time + PLAYBACK_OBJECTS_OFFSET);
            var end:Number = (start + duration);
            for (start; start <= end; start++) {
                var existingTask:AnnotationTask = (_annotationTasks[start] as AnnotationTask);
                if (existingTask) {
                    _annotationTasks[start] = _mergeAnnotationTasks(existingTask, task);
                } else {
                    _annotationTasks[start] = task;
                }
            }
        }
    }

    /**
     * Adds one last annotation, whose job is to mark the end of the score.
     */
    private function _sealAnnotationRegions () : void {
        var endOfScoreTask : AnnotationTask = new AnnotationTask(
                new <AnnotationAction>[new AnnotationAction(OperationTypes.TYPE_CLOSE_SCORE, null)]);
        var start : uint = _annotationTasks.length;
        _pushAnnotationRegion(endOfScoreTask, start, SCORE_ITEM_ANNOTATION_WINDOW);
    }

    /**
     * Adds all actions inside given `sourceTask` to given `targetTask`, while skipping duplicates.
     *
     * @param   targetTask
     *          AnnotationTask to add AnnotationActions to.
     *
     * @param   sourceTask
     *          AnnotationTask to obtain new AnnotationActions from.
     *
     * @return  Returns the given `targetTask` AnnotationTask, possibly with some added AnnotationActions.
     */
    private static function _mergeAnnotationTasks(targetTask:AnnotationTask, sourceTask:AnnotationTask):AnnotationTask {
        var i:int;
        var targetActions:Vector.<AnnotationAction> = targetTask.actions;
        var srcActions:Vector.<AnnotationAction> = sourceTask.actions;
        var numSrcActions:uint = srcActions.length;
        var srcAction:AnnotationAction;
        for (i = 0; i < numSrcActions; i++) {
            srcAction = srcActions[i];
            if (!_exists(srcAction, targetActions)) {
                targetActions.push(srcAction);
            }
        }
        return targetTask;
    }

    /**
     * Searches given `action` within given `inActions` and returns `true` if a match is found. For two actions to
     * match, they must have the same "type" and "targetId".
     *
     * @param   action
     *          An AnnotationAction instance to search a match for.
     *
     * @param   inActions
     *          A Vector of AnnotationAction instances to test against the given AnnotationAction.
     *
     * @return  `True` if a match for `action` is found inside `inActions`, false otherwise.
     */
    private static function _exists(action:AnnotationAction, inActions:Vector.<AnnotationAction>):Boolean {
        var i:int;
        var numActions:uint = inActions.length;
        var testAction:AnnotationAction;
        for (i = 0; i < numActions; i++) {
            testAction = inActions[i];
            if (testAction.type == action.type && testAction.targetId == action.targetId) {
                return true;
            }
        }
        return false;
    }

}
}
