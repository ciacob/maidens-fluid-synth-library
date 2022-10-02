package eu.claudius.iacob.synth.sound.map {
public class AnnotationTask {

    public var done : Boolean;

    private var _actions:Vector.<AnnotationAction>;

    /**
     * Container for one or more AnnotationAction instances; essentially groups together the "things to be done"
     * when the playhead reaches a specific portion of the pre-rendered audio material.
     *
     * @param   actions
     *          List of AnnotationAction instances, where each AnnotationAction describes a single operation
     *          to be carried on the object ointed to by the given `targetId`.
     */
    public function AnnotationTask(actions:Vector.<AnnotationAction>) {
        _actions = actions;
    }

    public function get actions():Vector.<AnnotationAction> {
        return _actions;
    }

    /**
     * @see Object.toString()
     */
    public function toString () : String {
        return 'AnnotationTask | Actions:\n\t' + _actions.join ('\n\t');
    }
}
}
