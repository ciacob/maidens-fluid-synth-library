package eu.claudius.iacob.synth.sound.map {
import ro.ciacob.utils.Strings;

public class NoteTrackObject extends TrackObject {
    private var _id:String;
    private var _attackList:Vector.<NoteAttackInfo>;
    private var _timeOffset:int;
    private var _velocityOffset:Number;
    private var _volumeOffset:Number;
    private var _panOffset:Number;

    /**
     * Track-assignable entity that is directly responsible with playing and/or releasing notes.
     * In MIDI terms, a NoteTrackObject is essentially a producer of "noteOn" and/or "noteOff" messages
     * that are to be issued simultaneously. Also, a NoteTrackObject can cause a number of side effects,
     * such as producing CC messages right before and/or after the "note..." messages (e.g., a NoteTrackObject
     * could issue a CC7 message to turn up volume right before playing a chord, just in case mere velocity
     * won't do).
     *
     * @param   attackList
     *          Vector of NoteAttackInfo objects containing information about the notes to be played. A MIDI
     *          "noteOn" message will be produced for each element in this list. Optional. If not given, a
     *          "musical rest" is assumed.
     *
     * @param   id
     *          Optional. Globally unique id that identifies this NoteTrackObject. If not given, one is provided
     *          automatically.
     *
     * @param   timeOffset
     *          Offset, in milliseconds, to globally delay or expedite (on the timeline) all the MIDI messages
     *          this NoteTrackObject will produce. The `timeOffset` argument is intended to be used in implementing
     *          "humane playback", i.e., adding some degree of randomness into the performance to have it sound
     *          less like it was produced by a machine. Positive values delay, negative values expedite. Optional,
     *          defaults to 0.
     *
     * @param   velocityOffset
     *          Offset, expressed as a percent of the parent Track's current "base velocity" value. It globally
     *          increases or decreases the velocity of all "noteOn" messages this NoteTrackObject will produce.
     *          This global `velocityOffset` argument is intended to be used in implementing (metric) stress
     *          (i.e., being able to strum a chord louder in its entirety, as opposed to playing some of its
     *          pitches louder, which is a job for the `velocityOffset` argument of the NoteAttackInfo class'
     *          constructor).
     *          Example: `0.5` reduces the base velocity value to half, while `2` doubles it. Out of range values
     *          will be automatically corrected. Changes are volatile, i.e., the base value is not, itself, modified.
     *          Optional, defaults to `1`, which has no effect.
     *
     * @param   volumeOffset
     *          Offset, expressed as a percent of the parent Track's current "base volume" value. Intended to support
     *          phrasing and stress when velocity alone may not provide sufficient dynamic separation.
     *          Example: 0.5 reduces the base volume to half, while `2` doubles it. Out of range values will be
     *          automatically corrected. Changes are volatile, i.e., the base value is not, itself, modified.
     *          Optional, defaults to `1`, which has no effect.
     *
     * @param   panOffset
     *          Offset, expressed as a percent of the parent Track's current "base pan" value. Intended to support
     *          the scenario where stereophonic placement needs to be altered on the fly during performance. Note
     *          that this argument pans a chord entirely, as opposed to the `panOffset` argument of the
     *          NoteAttackInfo class' constructor, which can refine the effect by further stereo shifting individual
     *          pitches.
     *          Example: `0.5` reduces the base pan value to half, while `2` doubles it. Changes are volatile, i.e.,
     *          the base value is not, itself, modified. Optional, defaults to `1`, which leaves the base value
     *          unmodified.
     *
     */
    public function NoteTrackObject(attackList:Vector.<NoteAttackInfo> = null,
                                    id:String = null,
                                    timeOffset:int = 0,
                                    velocityOffset:Number = 1,
                                    volumeOffset:Number = 1,
                                    panOffset:Number = 1
    ) {
        _id = (id || Strings.UUID);
        super(TrackObject.TYPE_NOTE, _id);
        _attackList = attackList;
        _timeOffset = timeOffset;
        _velocityOffset = velocityOffset;
        _volumeOffset = volumeOffset;
        _panOffset = panOffset;
    }

    public function get attackList():Vector.<NoteAttackInfo> {
        return _attackList;
    }

    public function get timeOffset():int {
        return _timeOffset;
    }

    public function get velocityOffset():Number {
        return _velocityOffset;
    }

    public function get volumeOffset():Number {
        return _volumeOffset;
    }

    public function get panOffset():Number {
        return _panOffset;
    }
}
}
