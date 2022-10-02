package eu.claudius.iacob.synth.sound.map {
import eu.claudius.iacob.synth.constants.OperationTypes;
import eu.claudius.iacob.synth.constants.PayloadKeys;
import eu.claudius.iacob.synth.constants.SamplesRenderingScope;
import eu.claudius.iacob.synth.constants.SeekScope;
import eu.claudius.iacob.synth.utils.TrackDescriptor;

public class Timeline {

    private var _readStartTime:int = 0;
    private var _readEndTime:int = int.MAX_VALUE;
    private var _preProcessor:ITracksPreProcessor;
    private var _tracks:Vector.<Track>;
    private var _labels:Object;

    /**
     * Essentially, the Timeline is a bi-dimensional sparse Array of TrackObjects.
     *
     * These are plotted at indices that match their time assignment (e.g., a TrackObject plotted from index 1000 onward
     * is supposed to start "doing something" 1000 milliseconds into the playback time).
     *
     * Once plotted, the Timeline is then read back synchronously, index by index. When spans of contiguous,
     * identical TrackObjects are found on an index, they cause the synth to be actioned according to their type and
     * payload (e.g., invoking the synth's `noteOn()` or `noteOff()` methods). Immediately after the synth is acted
     * upon, sample requests are issued.
     *
     * @constructor
     */
    public function Timeline() {
        _tracks = new Vector.<Track>;
        _labels = {};
    }

    /**
     * Registers an instance of a Track object, so that its content is available for being sent to the synth.
     * @param   track
     *          The Track to add. Note that there cannot be several Tracks with the same id.
     *
     * @return  `True` if the Track was accepted, `false` otherwise (e.g., because one with the same id
     *          already exists).
     */
    public function addTrack(track:Track):Boolean {
        var matches:Vector.<Track> = _findTracksById(track.id);
        if (matches.length == 0) {
            _tracks.push(track);
            return true;
        }
        return false;
    }

    /**
     * Returns a read-only list of the Track objects currently registered with this Timeline. Tracks cannot be
     * unregistered by removing them from the returned collection, but they can be acted upon, e.g., they can be
     * muted or unmuted.
     * @return
     */
    public function getTracks():Vector.<Track> {
        return _tracks.concat();
    }

    /**
     * Unregisters a previously registered Track instance.
     * @param   track
     *          The Track to remove.
     *
     * @return  `True` if the Track was found and removed, `false` if the Track was not found.
     */
    public function removeTrack(track:Track):Boolean {
        var matches:Vector.<Track> = _findTracksById(track.id);
        if (matches.length == 1) {
            var indexToRemove:int = (matches[0].data as int);
            _tracks.splice(indexToRemove, 1);
            return true;
        }
        return false;
    }

    /**
     * Unregisters all previously registered Track instances. Does not touch set labels or start/end markers, (which
     * could thus point to invalid positions after this method is called).
     */
    public function empty () : void {
        _tracks.length = 0;
    }

    /**
     * Sets the start time, in milliseconds, for reading back the Timeline.
     * @param time
     */
    public function setReadStartTime(time:Number):void {
        if (time < 0) {
            time = 0;
        }
        _readStartTime = time;
    }

    /**
     * Sets the end time, in milliseconds, for reading back the Timeline.
     * @param time
     */
    public function setReadEndTime(time:Number):void {
        if (time < 0) {
            time = 0;
        }
        _readEndTime = time;
    }

    /**
     * Sets an already registered label, by its name, from which to start reading back from the Timeline.
     * @param   name
     *          The name of the label to start reading back from.
     *
     * @return  `True` if given label was successfully found and resolved to a start time; `false` otherwise.
     */
    public function setReadStartLabel(name:String):Boolean {
        if (name in _labels) {
            setReadStartTime(_labels[name]);
            return true;
        }
        return false;
    }

    /**
     * Sets an already registered label, by its name, up to which to read back from the Timeline.
     *
     * @param   name
     *          The name of the label to stop reading back at.
     *
     * @return  `True` if given label was successfully found and resolved to an end time; `false` otherwise.
     */
    public function setReadEndLabel(name:String):Boolean {
        if (name in _labels) {
            setReadEndTime(_labels[name]);
            return true;
        }
        return false;
    }

    /**
     * Marks the entire span of the Timeline to be read back.
     */
    public function setFullRead():void {
        _readStartTime = 0;
        _readEndTime = int.MAX_VALUE;
    }

    /**
     * Registers an arbitrary name (a "label") as pointing to a specific time on the Timeline.
     *
     * NOTES:
     * Label names should be unique, but if they are not, they override each other, i.e., if you register time
     * `1235` to label `A`, and then try to register time `1500` to some (other) label called `A`, then you will end
     * up with only one label `A`, that points to time `1500`.
     *
     * Labels are not dynamic, meaning that they do not update based on what might happen in Tracks. If you modify
     * Tracks content, then you must manually rebuild labels to reflect the new reality.
     *
     * @param   name
     *          The name to use for the label; should be unique; in case o conflicts, the last registered wins.
     *
     * @param   time
     *          The point in time, in milliseconds, to associate with given `name`. There can be several names
     *          referring to the same point in time.
     */
    public function setLabel(name:String, time:Number):void {
        _labels[name] = time;
    }

    /**
     * Unregisters a label previously registered using `setLabel()`.
     *
     * @param   name
     *          The name of the label to unregister.
     *
     * @return  `True` if removal was successful, false otherwise (e.g., the name might not have been found).
     */
    public function unsetLabel(name:String):Boolean {
        if (name in _labels) {
            delete _labels[name];
            return true;
        }
        return false;
    }

    /**
     * Unregisters a label previously registered using `setLabel()`, by looking up its associated time. If several
     * labels are associated to the same time, all are removed/unregistered.
     *
     * @param   time
     *          A label's registered time, to do a reverse look-up by.
     *
     * @param   allowance
     *          The amount of variation, in milliseconds, to tolerate for given `time`, i.e., actual label's
     *          time might be within that much error margin (either positive or negative). Optional, defaults to 0.
     *
     * @return  The number of labels actually removed.
     */
    public function unsetLabelAt(time:int, allowance:int = 0):int {
        var numLabelsRemoved:int = 0;
        var matches:Vector.<String> = _getLabelsByTime(time, allowance);
        var i:int;
        var match:String;
        var numMatches:int = matches.length;
        for (i = 0; i < numMatches; i++) {
            match = matches[i];
            if (delete (_labels[match])) {
                numLabelsRemoved++;
            }

        }
        return numLabelsRemoved;
    }

    /**
     * Unregisters any label ever registered.
     */
    public function clearAllLabels():void {
        unsetLabelAt(0, int.MAX_VALUE);
    }

    /**
     * Convenience method to set the "solo" flag in bulk, for several given Track instances.
     *
     * @param   solos
     *          A Vector of TrackDescriptor instances to provide information about the Tracks to be soloed.
     *
     * @return  `True` if all the requested Tracks were successfully acted upon, false otherwise.
     */
    public function applySolos (solos : Vector.<TrackDescriptor>) : Boolean {
        var i : int;
        var numDescriptors : uint = solos.length;
        var descriptor : TrackDescriptor;
        var matches : Vector.<Track>;
        var track : Track;
        for (i = 0; i < numDescriptors; i++) {
            descriptor = solos[i];
            matches = _findTracksById (track.id);
            if (!matches || matches.length != 1) {
                return false;
            }
            track = matches[0];
            track.solo();
        }
        return true;
    }

    /**
     * Convenience method to remove the "solo" flag in bulk, from all registered Track instances.
     */
    public function setNoSolos () : void {
        var i : int;
        var numTracks : uint = _tracks.length;
        var track : Track;
        for (i = 0; i < numTracks; i++) {
            track = _tracks[i];
            track.unSolo();
        }
    }

    /**
     * Convenience method to set the "mute" flag in bulk, for several given Track instances.
     *
     * @param   mutes
     *          A Vector of TrackDescriptor instances to provide information about the Tracks to be muted.
     *
     * @return  `True` if all the requested Tracks were successfully acted upon, false otherwise.
     */
    public function applyMutes (mutes : Vector.<TrackDescriptor>) : Boolean {
        var i : int;
        var numDescriptors : uint = mutes.length;
        var descriptor : TrackDescriptor;
        var matches : Vector.<Track>;
        var track : Track;
        for (i = 0; i < numDescriptors; i++) {
            descriptor = mutes[i];
            matches = _findTracksById (track.id);
            if (!matches || matches.length != 1) {
                return false;
            }
            track = matches[0];
            track.mute();
        }
        return true;
    }

    /**
     * Convenience method to remove the "mute" flag in bulk, from all registered Track instances.
     */
    public function setNoMutes () : void {
        var i : int;
        var numTracks : uint = _tracks.length;
        var track : Track;
        for (i = 0; i < numTracks; i++) {
            track = _tracks[i];
            track.unMute();
        }
    }

    /**
     * Registers an optional handler to preprocess Tracks material before sending it to the synth. The typical use
     * would be to alter velocity, volume and/or start time / end time in order to increase degree of realism of
     * played back material.
     *
     * @param preProcessor
     */
    public function setPreProcessor(preProcessor:ITracksPreProcessor):void {
        _preProcessor = preProcessor;

    }

    /**
     * Unregisters set preprocessor if applicable.
     */
    public function unsetPreProcessor():void {
        _preProcessor = null;
    }

    /**
     * Returns a bidimensional Array, where each higher order Array contains a collection of
     * Objects that describe the precise tasks the synth has to carry on in order to produce
     * music for each Track (tasks such as initializing or releasing a synth instance, triggering
     * noteOn, noteOff or CC MIDI messages, requesting samples to be produced, etc).
     *
     * @param   sortByPreset
     *          Orders Track instances by their preset number, so that all the Tracks with the
     *          same preset number are rendered together, regardless of the order tracks were originally defined in.
     *          Optional, default true.
     *
     *          NOTE: due to limitations in the current synthesizer engine, exported tracks must always be ordered
     *          for the rendered audio to use the correct instruments timbre.
     */
    public function readOn(sortByPreset:Boolean = true):Array {
        var flattenedTracks:Array = [];
        var flattenedTrack:Array;
        var instruction:Object;

        // Decide which tracks need to actually be played back, based on their "mute" and "solo"
        // properties.
        var i:int;
        var track:Track;
        var soloTracks:Vector.<Track> = new Vector.<Track>;
        var playableTracks:Vector.<Track> = new Vector.<Track>;
        var numTracks:int = _tracks.length;
        for (i = 0; i < numTracks; i++) {
            track = _tracks[i];
            if (track.isMuted) {
                continue;
            }
            if (track.isSoloed) {
                soloTracks.push(track);
                continue;
            }
            playableTracks.push(track);
        }
        var tracksToExport:Vector.<Track> = (soloTracks.length > 0) ? soloTracks : playableTracks;
        if (sortByPreset) {
            tracksToExport.sort(_byPreset);
        }

        // Walk each track and extract a sequence of low-level actions from it.
        numTracks = tracksToExport.length;
        var k:int;
        var L:int;

        var numFrames:int;
        var numObjects:int;
        var objects:Vector.<TrackObject>;
        var object:TrackObject;
        var objectWindow:TrackObjectWindow;
        var objectWindowStart : int;
        var annotationObject:AnnotationTrackObject;
        var scoreAnnotation:ScoreItemAnnotation;
        var noteObject:NoteTrackObject;
        var noteTime:int;
        var noteDuration:int;
        var noteVelocity:int;
        var noteVolume:int;
        var notePan:int;
        var notePreset:int;
        var noteId:String;
        var numNoteAttacks:int;
        var noteAttacks:Vector.<NoteAttackInfo>;
        var noteAttack:NoteAttackInfo;
        var attackPitch:int;
        var attackVelocity:int;
        var attackTime:int;
        var attackDuration:int;
        var attackPan:int;
        var attackTiesLeft:Boolean;
        var attackTiesRight:Boolean;
        var attackTies:Boolean;
        var tieGroupId : String;
        var instructionId : String;
        for (i = 0; i < numTracks; i++) {
            if (flattenedTracks[i] === undefined) {
                flattenedTrack = [];
                flattenedTracks[i] = flattenedTrack;
            }
            track = tracksToExport[i];
            numFrames = Math.max (0, (Math.min (_readEndTime, track.numFrames) - _readStartTime));

            // If "_readStartTime" is higher than "_readEndTime", there will be no frames to read anyway, so we skip to
            // the next Track available, if any.
            if (numFrames == 0) {
                continue;
            }

            objects = track.getObjectsAt(_readStartTime, numFrames, 1);
            numObjects = objects.length;
            for (L = 0; L < numObjects; L++) {
                object = objects[L];
                objectWindow = track.getObjectWindow(object, true);
                objectWindowStart = Math.max(0, objectWindow.startTime - _readStartTime);

                switch (object.$type) {
                    case TrackObject.TYPE_ANNOTATION:
                        annotationObject = (object as AnnotationTrackObject);

                        // For the time being, we are only interested in score item annotations.
                        if (annotationObject is ScoreItemAnnotation) {
                            scoreAnnotation = (annotationObject as ScoreItemAnnotation);
                            instruction = makeInstructionStorage();
                            instruction[PayloadKeys.ID] = object.id;
                            instruction[PayloadKeys.TYPE] = OperationTypes.TYPE_HIGHLIGHT_SCORE_ITEM;
                            instruction[PayloadKeys.SCORE_ITEM_ID] = scoreAnnotation.scoreItemId;
                            instruction[PayloadKeys.TIME] = objectWindowStart;
                            instruction[PayloadKeys.DURATION] = objectWindow.timeSpan;
                            flattenedTrack.push(instruction);
                        }
                        break;
                    case TrackObject.TYPE_NOTE:
                        noteObject = (object as NoteTrackObject);
                        noteAttacks = noteObject.attackList;
                        numNoteAttacks = noteAttacks.length;
                        noteTime = (objectWindowStart + noteObject.timeOffset);
                        noteDuration = objectWindow.timeSpan;
                        noteVelocity = _ensureMidiRange(track.baseVelocity * noteObject.velocityOffset);
                        noteVolume = _ensureMidiRange(track.baseVolume * noteObject.volumeOffset)
                        notePan = _ensureMidiRange(track.basePan * noteObject.panOffset);
                        notePreset = _ensureMidiRange(track.preset);
                        noteId = noteObject.id;
                        for (k = 0; k < numNoteAttacks; k++) {
                            noteAttack = noteAttacks[k];
                            attackTiesLeft = noteAttack.tiesLeft;
                            attackTiesRight = noteAttack.tiesRight;
                            attackTies = (attackTiesLeft || attackTiesRight);
                            tieGroupId = noteAttack.tieGroupId;
                            instructionId = attackTies? tieGroupId : noteId;
                            attackPitch = noteAttack.pitchIndex;
                            attackVelocity = _ensureMidiRange(noteVelocity * noteAttack.velocityOffset);
                            attackPan = _ensureMidiRange(notePan * noteAttack.panOffset)
                            attackTime = (noteTime + noteAttack.timeOffset);
                            attackDuration = (noteDuration + noteAttack.durationOffset);

                            // For each attack of this NoteObject, we need to:
                            // 1. Seek to its start point. This seeks inside the main samples storage.
                            if (!attackTiesLeft) {
                                instruction = makeInstructionStorage();
                                instruction[PayloadKeys.ID] = instructionId;
                                instruction[PayloadKeys.TYPE] = OperationTypes.TYPE_SEEK_TO;
                                instruction[PayloadKeys.TIME] = attackTime;
                                instruction[PayloadKeys.SEEK_SCOPE] = SeekScope.START_OF_NOTE_HEAD;
                                flattenedTrack.push(instruction);
                            }

                            // 2. Issue a "noteOn" message
                            if (!attackTiesLeft) {
                                instruction = makeInstructionStorage();
                                instruction[PayloadKeys.ID] = instructionId;
                                instruction[PayloadKeys.TYPE] = OperationTypes.TYPE_NOTE_ON;
                                instruction[PayloadKeys.PRESET] = notePreset;
                                instruction[PayloadKeys.KEY] = attackPitch;
                                instruction[PayloadKeys.VELOCITY] = attackVelocity;
                                flattenedTrack.push(instruction);
                            }

                            // 3. Request samples that cover its entire duration: this
                            //    will produce the "head" and "body" of the sound.
                            instruction = makeInstructionStorage();
                            instruction[PayloadKeys.ID] = instructionId;
                            instruction[PayloadKeys.TYPE] = OperationTypes.TYPE_REQUEST_SAMPLES;
                            instruction[PayloadKeys.RENDER_SCOPE] = SamplesRenderingScope.RENDER_NOTE_HEAD;
                            instruction[PayloadKeys.DURATION] = attackDuration;
                            instruction[PayloadKeys.PRESET] = notePreset;
                            instruction[PayloadKeys.PAN] = attackPan;
                            flattenedTrack.push(instruction);

                            // 4. Issue a "noteOff" message
                            if (!attackTiesRight) {
                                instruction = makeInstructionStorage();
                                instruction[PayloadKeys.ID] = instructionId;
                                instruction[PayloadKeys.TYPE] = OperationTypes.TYPE_NOTE_OFF;
                                instruction[PayloadKeys.PRESET] = notePreset;
                                instruction[PayloadKeys.KEY] = attackPitch;
                                flattenedTrack.push(instruction);
                            }

                            // 5. Request as many samples as are needed to cover the full "tail", or "release"
                            // of the sound.
                            if (!attackTiesRight) {
                                instruction = makeInstructionStorage();
                                instruction[PayloadKeys.ID] = instructionId;
                                instruction[PayloadKeys.TYPE] = OperationTypes.TYPE_REQUEST_SAMPLES;
                                instruction[PayloadKeys.RENDER_SCOPE] = SamplesRenderingScope.RENDER_NOTE_TAIL;
                                instruction[PayloadKeys.PRESET] = notePreset;
                                instruction[PayloadKeys.PAN] = attackPan;
                                flattenedTrack.push(instruction);
                            }
                        }
                        break;
                }
            }

        }
        return flattenedTracks;
    }

    /**
     * Utility method to produce a Value Object ready for receiving synth instructions as payload. As opposed to regular
     * Objects, the returned Object comes with built-in debuging utilites.
     */
    private function makeInstructionStorage () : Object {
        var obj : Object = {};
        obj.toString = function () : String {
            var type : String = obj[PayloadKeys.TYPE];
            var idPart : String = obj[PayloadKeys.ID].split('-').pop();
            switch (type) {
                case OperationTypes.TYPE_SEEK_TO:
                    return (' { ' + type + ' @' + obj[PayloadKeys.TIME] + ' # ' + idPart + ' } ');
                default:
                    return (' { ' + type + ' #' + idPart + ' } ');
            }
        };
        return obj;
    }

    /**
     * Ensures `rawValue` is a positive integer between `0` and `126`, including both ends.
     * @param rawValue
     * @return
     */
    private function _ensureMidiRange(rawValue:Number):uint {
        rawValue = Math.round(rawValue);
        if (rawValue < 0) {
            rawValue = 0;
        }
        if (rawValue > 126) {
            rawValue = 126;
        }
        return (rawValue as uint);
    }

    /**
     * Looks up a registered Track by its `trackId`. Returns results in a Vector, but there should only be
     * zero or one results. The `data` property of the matching Track will contain its index in the parent tracks
     * collection.
     */
    private function _findTracksById(trackId:String):Vector.<Track> {
        var i:int;
        var matches:Vector.<Track> = new Vector.<Track>;
        var tmpTrack:Track;
        var numTracks:int = _tracks.length;
        for (i = 0; i < numTracks; i++) {
            tmpTrack = _tracks[i];
            if (tmpTrack.id == trackId) {
                tmpTrack.data = i;
                matches.push(tmpTrack);
            }
        }
        return matches;
    }

    /**
     * Looks up all registered labels under a given time. Returns results in a Vector.
     * @param   time
     *          The time, in milliseconds, to do a reverse label lookup by.
     *
     * @param   allowance
     *          The amount of variation, in milliseconds, to tolerate for given `time`, i.e., actual label's
     *          time might be within that much error margin (either positive or negative). Optional, defaults to 0.
     *
     * @return  A (possibly empty) collection of matching label names.
     */
    private function _getLabelsByTime(time:int, allowance:int = 0):Vector.<String> {
        var labelName:String;
        var labelTime:int;
        var delta:int;
        var matches:Vector.<String> = new Vector.<String>;
        for (labelName in _labels) {
            labelTime = (_labels[labelName] as int);
            delta = Math.abs(labelTime - time);
            if (delta <= allowance) {
                matches.push(labelName);
            }
        }
        return matches;
    }

    /**
     * Sorting method to be used for ordering Track instances by their preset number (so that all the Tracks with the
     * same preset number are rendered together, regardless of the order tracks were originally defined in).
     *
     * @param   trackA
     *          Track to be compared.
     *
     * @param   trackB
     *          Track to compare to.
     *
     * @return  An integer, according to the `Array.sort` method specification.
     */
    private function _byPreset(trackA:Track, trackB:Track):int {
        return (trackA.preset - trackB.preset);
    }

}
}
