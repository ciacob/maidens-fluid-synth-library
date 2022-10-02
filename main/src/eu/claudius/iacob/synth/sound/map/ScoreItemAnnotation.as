package eu.claudius.iacob.synth.sound.map {
public class ScoreItemAnnotation extends AnnotationTrackObject {

    /**
     * Convenience type meant to represent an annotation whose sole purpose is highlighting elements on a musical
     * score (e.g., notes or chords) in sync with their pre-rendered recording.
     *
     * @param   scoreItemId
     *          An unique id representing a musical score item to be highlighted.
     */
    public function ScoreItemAnnotation (scoreItemId : String) {
        super (scoreItemId);
    }

    public function get scoreItemId () : String {
        return super.annotation;
    }
}
}
