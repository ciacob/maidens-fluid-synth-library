package eu.claudius.iacob.synth.events {
import flash.events.Event;
import flash.filesystem.File;
import flash.utils.ByteArray;

public class SoundFontLoadedEvent extends Event {

    public static const SOUND_FONT_AVAILABILITY_EVENT:String = 'soundFontAvailabilityEvent';

    private var _soundFontData:ByteArray;
    private var _soundFontFile:File;

    /**
     * Event to dispatch when a sound font (*.sf2 file) has become available.
     *
     * @param   soundFontData
     *          The actual data inside the file, in its original (raw) form.
     *
     * @param   soundFontFile
     *          A File object representing the *.sf2 file that was loaded.
     */
    public function SoundFontLoadedEvent(soundFontData:ByteArray, soundFontFile:File) {
        super(SOUND_FONT_AVAILABILITY_EVENT);
        _soundFontData = soundFontData;
        _soundFontFile = soundFontFile;
    }

    /**
     * The actual data inside the file, in its original (raw) form.
     */
    public function get soundFontData():ByteArray {
        return _soundFontData;
    }

    /**
     * A File object representing the *.sf2 file that was loaded.
     */
    public function get soundFontFile():File {
        return _soundFontFile;
    }

    /**
     * @see flash.events.Event.clone
     */
    override public function clone():Event {
        return new SoundFontLoadedEvent(_soundFontData, _soundFontFile);
    }
}
}
