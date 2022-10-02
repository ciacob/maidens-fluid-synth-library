package eu.claudius.iacob.synth.events {
import flash.events.Event;

public class PlaybackAnnotationEvent extends Event {

        public static const PLAYBACK_ANNOTATION_EVENT:String = 'playbackAnnotationEvent';

        private var _payload:Object;

        /**
         * Event to dispatch when a previously registered annotation is to be activated (e.g., when it is about time to
         * highlight a note on a musical score because its corresponding sound has triggered).
         *
         * @param   payload
         *          The annotation body; actual data type varies.
         */
        public function PlaybackAnnotationEvent(payload : Object) {
            super (PLAYBACK_ANNOTATION_EVENT);
            _payload = payload;
        }

        /**
         * The annotation body; actual data type varies.
         */
        public function get payload () : Object {
            return _payload;
        }

        /**
         * @see flash.events.Event.clone
         */
        override public function clone () : Event {
            return new PlaybackAnnotationEvent (_payload);
        }
    }
}
