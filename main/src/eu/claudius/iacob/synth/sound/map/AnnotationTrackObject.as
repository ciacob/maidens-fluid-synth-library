package eu.claudius.iacob.synth.sound.map {
import ro.ciacob.utils.Strings;

public class AnnotationTrackObject extends TrackObject {

    private var _id : String;
    private var _annotation : String;
    private var _payload : Object;

    /**
     * Track-assignable entity that is directly responsible with triggering actions that are synchronized to the
     * music being played, such as highlighting notes on a musical score as they sound.
     * This type of entity has no direct MIDI equivalent.
     *
     * @param   annotation
     *          String describing this AnnotationTrackObject, e.g., the identifier of a graphical score element to
     *          highlight. Optional, but if missing, `payload` is mandatory.
     *
     * @param   id
     *          Optional. Globally unique id that identifies this AnnotationTrackObject. If not given, one is provided
     *          automatically.
     *
     * @param   payload
     *          Complex data to describe this AnnotationTrackObject, if a mere String won't do. Optional, but if missing,
     *          `annotation` is mandatory
     */
    public function AnnotationTrackObject(annotation : String = null, id : String = null, payload : Object = null) {
        _id = (id || Strings.UUID);
        super (TrackObject.TYPE_ANNOTATION, _id);
        if (annotation == null && payload == null) {
            throw ('`Annotation` and `payload` arguments cannot both be null when creating an AnnotationTrackObject.');
        }
        _annotation = annotation;
        _payload = payload;
    }

    /**
     * String describing this AnnotationTrackObject, e.g., the identifier of a graphical score element to highlight.
     */
    public function get annotation():String {
        return _annotation;
    }

    /**
     * Complex data to describe this AnnotationTrackObject, if a mere String won't do.
     */
    public function get payload():Object {
        return _payload;
    }
}
}
