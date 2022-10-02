package eu.claudius.iacob.synth.sound.map {
public class AnnotationAction {

    private var _type : String;
    private var _targetId:String;

    /**
     * Defines one job to be done when the playhead reaches a specific portion of the pre-rendered audio material.
     * One or more AnnotationAction instances are packed inside an AnnotationAction group.
     *
     * @param   type
     *          String defining the type of action to be carried on on the target denoted by given `targetId`.
     *
     * @param   targetId
     *          A String denoting an object that is to receive, or to "benefit from" all the operations described
     *          by the given `actions` list.
     */
    public function AnnotationAction(type : String, targetId:String) {
        _type = type;
        _targetId = targetId;
    }

    /**
     * @see Object.toString()
     */
    public function toString () : String {
        return ('AnnotationAction: ' + _type + ' | ' + targetId);
    }

    public function get type():String {
        return _type;
    }

    public function get targetId():String {
        return _targetId;
    }
}
}
