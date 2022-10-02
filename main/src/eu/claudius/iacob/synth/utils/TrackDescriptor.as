package eu.claudius.iacob.synth.utils {
public class TrackDescriptor {

    private var _name:String;
    private var _preset:uint;
    private var _voices:Vector.<uint>;
    private var _uid:String;

    /**
     * Helper class to briefly group all information needed to create a Track instance
     * (eu.claudius.iacob.synth.sound.map.Track). Also usable for defining mutes and solos (when we support them).
     *
     * @param   name
     *          The name of the Track.
     *
     * @param   preset
     *          The Track's preset (responsible for its musical timbre, e.g., preset 40 will use a Violin sound for
     *          playback).
     *
     * @param   voices
     *          Optional. If defined, it is expected to contain a list of voice indices (e.g., `1,2,3,4` will refer to
     *          all the voices a Piano track usually has); indices are 1-based. To be used when further refining mutes
     *          and solos (e.g., to only solo the second voice of a Harp, you pass `Vector.<uint>[2]` to this argument.
     *
     * @param   uid
     *          Optional. General-purpose field to be used for storing a value that uniquely identifies the Track to be
     *          created.
     */
    public function TrackDescriptor(name:String, preset:uint, voices:Vector.<uint> = null, uid:String = null) {
        _name = name;
        _preset = preset;
        _voices = voices;
        _uid = uid;
    }

    public function get name():String {
        return _name;
    }

    public function get preset():uint {
        return _preset;
    }

    public function get voices():Vector.<uint> {
        return _voices;
    }

    public function get uid():String {
        return _uid;
    }
}
}
