package eu.claudius.iacob.synth.sound.map {
import ro.ciacob.utils.Strings;

/**
 * Base class for actual data to be added to a Track.
 * @see eu.claudius.iacob.synth.sound.map.Track.
 * @subclasses NoteTrackObject
 */
public class TrackObject {
    public static const TYPE_NOTE:String = 'note';
    public static const TYPE_ANNOTATION:String = 'annotation';
    public static const TYPE_CC:String = 'cc'; // reserved for future use

    private var _$type:String;
    private var _id:String;

    /**
     * Base class for all entities that can be added to a Track.
     * @param $type
     * @param id
     */
    public function TrackObject($type:String, id:String = null) {
        _$type = $type;
        _id = (id || Strings.UUID);
    }

    public function get $type():String {
        return _$type;
    }

    public function get id():String {
        return _id;
    }
}
}
