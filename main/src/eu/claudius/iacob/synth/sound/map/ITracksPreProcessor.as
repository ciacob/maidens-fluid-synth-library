package eu.claudius.iacob.synth.sound.map {

    /**
     * An ITracksPreProcessor implementor is a handler that preprocesses Tracks material before sending it to the synth.
     * The typical use would be to alter velocity, volume and/or start time / end time in order to increase degree of
     * realism of played back material.
     */
    public interface ITracksPreProcessor {

        /**
         * Actually performs any due alteration of the original material. This method performs destructive work, i.e.,
         * the original data is changed in place. If a back-up is needed, it must be made outside this class.
         *
         * @param   tracks
         *          Collection of the tracks containing NoteTrackObjects. Note that is is not expected that the objects
         *          be relocated on the tracks, but their `offset` properties be used instead.
         */
        function process (tracks : Vector.<Track>) : void;
    }
}
