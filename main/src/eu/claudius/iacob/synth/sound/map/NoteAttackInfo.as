package eu.claudius.iacob.synth.sound.map {
    public class NoteAttackInfo {

        private var _pitchIndex : int;
        private var _velocityOffset : Number;
        private var _timeOffset : int;
        private var _durationOffset : int;
        private var _panOffset : Number;
        private var _tiesLeft : Boolean;
        private var _tiesRight : Boolean;
        private var _tieGroupId : String;

        /**
         * Container for all the specific information needed to produce a "noteOn" MIDI message. Data that is common
         * to several pitches (such as preset number) is not stored here, but instead it is inherited from the parent
         * NoteTrackObject. Potentially pitch-specific data (such as velocity), while inherited, can be further altered
         * via fine-tuning arguments, such as `velocityOffset`. Such arguments build upon the corresponding calculated
         * value of the parent NoteTrackObject, which, in turn, builds upon the base value of its parent Track.
         *
         * @see eu.claudius.iacob.synth.sound.map.Track
         * @see eu.claudius.iacob.synth.sound.map.NoteTrackObject
         * @see eu.claudius.iacob.synth.sound.map.TrackObject
         *
         * @param   pitchIndex
         *          The MIDI pitch to use in the produced "noteOn" message, 0 to 126, with `60` representing "middle C".
         *
         * @param   velocityOffset
         *          Offset, expressed as a percent of the parent NoteTrackObject's calculated velocity value.
         *          Only affects the related "noteOn" message.
         *          Example: `0.5` reduces the parent NoteTrackObject's velocity to half, while `2` doubles it.
         *          Out of range values will be automatically corrected. Changes are volatile, i.e., the parent
         *          NoteTrackObject's velocity value is not, itself, modified. Optional, defaults to `1`,
         *          which has no effect.
         *
         * @param   timeOffset
         *          Offset, in milliseconds, to delay or expedite (on the timeline) the produced "noteOn" message. This
         *          argument is intended to be used in implementing "arpegiatto" (strumming pitches of a chord, by
         *          giving each but the first note a slight delay). Can also increase degree of realism by deliberately
         *          avoiding precisely simultaneous note attack when reproducing chords. Positive values delay, negative
         *          values expedite. Optional, defaults to 0.
         *
         * @param   durationOffset
         *          Offset, in milliseconds, to delay or expedite (on the timeline) the produced "noteOff" message. This
         *          argument is intended to be used in implementing "arpegiatto" (strumming pitches of a chord, by
         *          giving each but the first note a slight delay). Can also increase degree of realism by deliberately
         *          avoiding precisely simultaneous note attack when reproducing chords. Positive values delay, negative
         *          values expedite. Optional, defaults to 0.
         *
         * @param   panOffset
         *          Non-standard, non-MIDI instruction to shift played ("attacked") note in stereo space. This will
         *          be directly handled at a lower-level by the synth, with no intervening MIDI messages. The argument
         *          is intended to be used with instruments that occupy a significant amount of physical space (e.g.,
         *          piano, organ, marimba, vibraphone, etc.), where stereophonically placing pitches by their
         *          frequencies makes sense, and adds to the realism of the produced sound (e.g., the lower pitches of
         *          the marimba will generally sound more "to the right" than the higher pitches of the same
         *          instrument). Works exactly like `velocityOffset` (see above) and takes parent NoteTrackObject's
         *          calculated pan value as a base. Optional, defaults to `1`, which has no effect.
         *
         * @param   tiesLeft
         *          If `true`, the "noteOn" message for this NoteAttackInfo will be omitted; combined with a `tiesRight`
         *          of `true` on the previous NoteAttackInfo of the same pitch, this will result in the implementation
         *          of a musical "tie", where a played note "holds onto" next one of the same pitch.
         *          Optional, default `false`.
         *
         * @param   tiesRight
         *          If `true`, the "noteOff" message for this NoteAttackInfo will be omitted; combined with a `tiesRight`
         *          of `true` on the next NoteAttackInfo of the same pitch, this will result in the implementation of a
         *          musical "tie", where a played note "holds onto" the next one of the same pitch.
         *          Optional, default `false`.
         *
         * @param   tieGroupId
         *          Unique identifier to apply to NoteAttackInfo instances being part of the same "tie group" (i.e.,
         *          being musically "tied" together via "tiesRight" and/or "tiesLeft"). Giving these instances a
         *          common id helps the client code treat them as a single entity (which they are, from a musical
         *          perspective, since two same-pitch notes that are "tied" sound like a single, longer note).
         */
        public function NoteAttackInfo (pitchIndex : int, velocityOffset : Number = 1, timeOffset : int = 0,
                                        durationOffset : int = 0, panOffset : Number = 1,
                                        tiesLeft : Boolean = false, tiesRight : Boolean = false,
                                        tieGroupId : String = null) {

            _pitchIndex = pitchIndex;
            _velocityOffset = velocityOffset;
            _timeOffset = timeOffset;
            _durationOffset = durationOffset;
            _panOffset = panOffset;
            _tiesLeft = tiesLeft;
            _tiesRight = tiesRight;
            _tieGroupId = tieGroupId;
        }

        public function get pitchIndex():int {
            return _pitchIndex;
        }

        public function get velocityOffset():Number {
            return _velocityOffset;
        }

        public function get timeOffset():int {
            return _timeOffset;
        }

        public function get durationOffset() : int {
            return _durationOffset;
        }

        public function get panOffset():Number {
            return _panOffset;
        }


        public function get tiesLeft():Boolean {
            return _tiesLeft;
        }

        public function get tiesRight():Boolean {
            return _tiesRight;
        }


        public function get tieGroupId():String {
            return _tieGroupId;
        }

        public function set tieGroupId(value:String):void {
            _tieGroupId = value;
        }
    }
}
