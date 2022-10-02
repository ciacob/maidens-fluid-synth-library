package eu.claudius.iacob.synth.events {
import flash.events.Event;

public class PlaybackPositionEvent extends Event {

    public static const PLAYBACK_POSITION_EVENT:String = 'playbackPositionEvent';

    private var _percent:Number;
    private var _position:uint;

    /**
     * Event to dispatch continuously while the playback position changes into the pre-recorded/pre-rendered
     * material.
     *
     * @param   percent
     *          The playback position to dispatch, as a (decimal) number between `0` (start of recording) and `1`
     *          (end of recording).
     *
     * @param   position
     *          The playback position as the number of milliseconds elapsed since playback was engaged. Typically,
     *          this is provided by the related SoundChannel object via its `position` property; see
     *          flash.media.SoundChannel.position for details.
     */
    public function PlaybackPositionEvent(percent:Number, position:uint) {
        super(PLAYBACK_POSITION_EVENT);
        _percent = percent;
        _position = position;
    }

    /**
     * The playback position to dispatch, as a (decimal) number between `0` (start of recording) and `1`
     * (end of recording).
     */
    public function get percent():Number {
        return _percent;
    }

    /**
     * The playback position as the number of milliseconds elapsed since playback was engaged. Typically,
     * this is provided by the related SoundChannel object via its `position` property; see
     * flash.media.SoundChannel.position for details.
     */
    public function get position():uint {
        return _position;
    }

    /**
     * @see flash.events.Event.clone()
     */
    override public function clone():Event {
        return new PlaybackPositionEvent(_percent, _position);
    }
}
}
