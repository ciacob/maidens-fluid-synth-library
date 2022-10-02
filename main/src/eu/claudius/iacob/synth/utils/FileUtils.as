package eu.claudius.iacob.synth.utils {
import eu.claudius.iacob.synth.constants.SynthCommon;
import eu.claudius.iacob.synth.events.SystemStatusEvent;

import flash.events.EventDispatcher;
import flash.events.IOErrorEvent;
import flash.events.OutputProgressEvent;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.utils.ByteArray;
import flash.utils.Endian;

import ro.ciacob.utils.constants.CommonStrings;

public class FileUtils extends EventDispatcher {

    private static const RIFF_HEADER:String = 'RIFF';
    private static const RIFF_CHUNK_SIZE_OFFSET:uint = 36;
    private static const WAVE_HEADER:String = 'WAVE';
    private static const SUB_CHUNK1_ID:String = 'fmt '; // mind the trailing space!
    private static const SUB_CHUNK1_SIZE:uint = 16;
    private static const PCM_AUDIO_FORMAT:uint = 1;
    private static const SAMPLE_RATE:uint = 44100;
    private static const BITS_PER_SAMPLE:uint = 16;
    private static const SUB_CHUNK2_ID:String = 'data';

    private var _fileBeingSaved : File;
    private var _outputListener : Function;
    private var _errorListener : Function;


    /**
     * Issues a streaming operation (actually delegates it to the `StreamingUtils` class), then asynchronously transfers
     * resulting bytes to given file.
     *
     * @param   streamer
     *          An instance of the `StreamingUtils` class that is already set up and ready to stream.
     *
     * @param   sounds
     *          An Object containing ByteArray instances, with each ByteArray containing the bytes loaded from a sound
     *          font file; @see `StreamingUtils.stream()` for details.
     *
     * @param   tracks
     *          Multidimensional Array that describes the music to be rendered as an ordered succession of instructions
     *          the synthesizer must execute;  @see `StreamingUtils.stream()` and `SynthProxy.preRenderAudio()` for
     *          details.
     *
     * @param   file
     *          A file where to store the resulting WAVE data; @see `FileUtils.dumpToDisk()` for details.
     *
     * @param   stereo
     *          Optional, default `false` (i.e., mono); @see `FileUtils.dumpToDisk()` for details.
     *
     * @throws  If this class was initialized with `null` for its constructor's `streamer` argument.
     */
    public function streamToDisk(streamer : StreamingUtils, sounds:Object, tracks:Array, file:File,
                                 stereo:Boolean = false):void {
        var _onStreamerReport : Function = function (event : SystemStatusEvent) : void {
            var report : ProgressReport = event.report;
            if (report.state == ProgressReport.STATE_STREAMING_DONE &&
                    report.subState == ProgressReport.SUBSTATE_NOTHING_TO_DO) {
                removeEventListener(SystemStatusEvent.REPORT_EVENT, _onStreamerReport);
                dumpToDisk (streamer.renderedAudioStorage, file, stereo);
            }
        }
        addEventListener(SystemStatusEvent.REPORT_EVENT, _onStreamerReport);
        streamer.stream(sounds, tracks, this);

    }

    /**
     * Asynchronously transfers given `soundBytes` to given `file`, as an 44100Hz, 16bits *.WAV mono or stereo file.
     * SystemStatusEvents are dispatched that monitor the process.
     *
     * @param   as3SoundBytes
     *          ByteArray containing sound samples in ActionScript format. These will be silently converted to WAVE
     *          format in the process (original sound date will not be touched).
     *
     * @param   file
     *          A file where to store the resulting WAVE data. It is assumed to be existing and writeable (this method
     *          does not check); runtime exceptions are thrown if it is not.
     *          NOTE: this method overwrites the given `file` if it exists. If you need to obtain confirmation from the
     *          user before overwriting existing file, you must obtain it EXTERNALLY, i.e., in your own code.
     *
     * @param   stereo
     *          Optional, default `false` (i.e., mono). Whether to mark the resulting *.WAV file as using 1 channel (`false`,
     *          the default), or two channels (`true`). Note that this does NOT attempt to convert the data inside
     *          `soundBytes`, which can result in the resulting file playing at the wrong speed if this argument is set
     *          incorrectly (because the existing material will be split or not onto two channels, thus altering the
     *          actual sampling rate).You must know whether the ActionScript sound was recorded in mono or in stereo,
     *          and you must set this parameter accordingly.
     *
     * @param   normalize
     *          Optional, default `false`. Whether to normalize given `soundBytes` prior to converting it to WAVE
     *          format. Normalization level is given by the `SynthCommon.CEIL_LEVEL` constant.
     */
    public function dumpToDisk(as3SoundBytes:ByteArray, file:File, stereo:Boolean = false,
                               normalize:Boolean = false):void {
        _fileBeingSaved = file;

        // Normalize audio if requested.
        if (normalize) {
            as3SoundBytes = AudioUtils.normalizeValues(as3SoundBytes, false);
        }

        // Convert from ActionScript sound format to WAVE sound format.
        var wavSoundBytes:ByteArray = _toWav16Format(as3SoundBytes);

        // Construct full *.WAV file structure in-memory. See: http://soundfile.sapp.org/doc/WaveFormat/
        // ----------------------------------------------------------------------------------------------
        var waveFileData:ByteArray = new ByteArray;
        waveFileData.endian = Endian.LITTLE_ENDIAN;

        // The canonical WAVE format starts with the RIFF header.
        // ChunkID: Contains the letters "RIFF" in ASCII form.
        waveFileData.writeUTFBytes(RIFF_HEADER);

        // ChunkSize: 36 + SubChunk2Size, or more precisely: 4 + (8 + SubChunk1Size) + (8 + SubChunk2Size). This is the
        // size of the rest of the chunk following this number. This is the size of the entire file in bytes minus 8
        // bytes for the two fields not included in this count: ChunkID and ChunkSize.
        var numWavSoundBytes:uint = wavSoundBytes.length;
        waveFileData.writeInt(numWavSoundBytes + RIFF_CHUNK_SIZE_OFFSET);

        // Format: Contains the letters "WAVE".
        waveFileData.writeUTFBytes(WAVE_HEADER);

        // The "WAVE" format consists of two subchunks: "fmt " and "data". The "fmt " subchunk describes the sound
        // data's format. Subchunk1ID: Contains the letters "fmt ".
        waveFileData.writeUTFBytes(SUB_CHUNK1_ID);

        // Subchunk1Size: 16 for PCM.  This is the size of the rest of the subchunk which follows this number.
        waveFileData.writeInt(SUB_CHUNK1_SIZE);

        // AudioFormat: PCM = 1 (i.e. Linear quantization). Values other than 1 indicate some form of compression.
        waveFileData.writeShort(PCM_AUDIO_FORMAT);

        // NumChannels: Mono = 1, Stereo = 2, etc.
        var numChannels:uint = stereo ? 2 : 1;
        waveFileData.writeShort(numChannels);

        // SampleRate: 8000, 44100, etc.
        waveFileData.writeInt(SAMPLE_RATE);

        // ByteRate: SampleRate * NumChannels * BitsPerSample / 8
        var byteRate:Number = (SAMPLE_RATE * numChannels * BITS_PER_SAMPLE) / 8;
        waveFileData.writeInt(byteRate);

        // BlockAlign: NumChannels * BitsPerSample / 8
        var blockAlign:Number = (numChannels * BITS_PER_SAMPLE) / 8;
        waveFileData.writeShort(blockAlign);

        // BitsPerSample: 8 bits = 8, 16 bits = 16, etc.
        waveFileData.writeShort(BITS_PER_SAMPLE);

        // The "data" subchunk contains the size of the data and the actual sound.
        // Subchunk2ID: Contains the letters "data".
        waveFileData.writeUTFBytes(SUB_CHUNK2_ID);

        // Subchunk2Size: NumSamples * NumChannels * BitsPerSample / 8
        // This is the number of bytes in the data. You can also think of this as the size of the read of the subchunk
        // following this number.
        waveFileData.writeInt(numWavSoundBytes);

        // Data: The actual sound data.
        waveFileData.writeBytes(wavSoundBytes);

        // Asynchronously transfer the *.WAV file structure to disk.
        var fileStream:FileStream = new FileStream;
        _outputListener = function (event : OutputProgressEvent) : void {
            _doOnProgressEvent(event);
        };
        _errorListener = function (event : IOErrorEvent) : void {
            _doOnIoError (event);
        }
        fileStream.addEventListener(OutputProgressEvent.OUTPUT_PROGRESS, _outputListener);
        fileStream.addEventListener(IOErrorEvent.IO_ERROR, _errorListener);
        fileStream.openAsync(file, FileMode.WRITE);
        fileStream.position = 0;
        fileStream.truncate();
        fileStream.writeBytes(waveFileData);
    }

    /**
     * Executed when OutputProgressEvents are fired from the FileStream instance responsible for writing the generated
     * *.wav file to disk. Redispatches progress information via our standardized SystemStatusEvent mechanism, and
     * closes the stream when there are no bytes left to be written.
     * @param event
     */
    private function _doOnProgressEvent (event : OutputProgressEvent) : void {
        var fileStream : FileStream = (event.target as FileStream);
        var bytesPending : Number = event.bytesPending;
        var bytesTotal : Number = event.bytesTotal;
        var percentUploaded : Number = ((bytesTotal - bytesPending) / bytesTotal);
        var report : ProgressReport = new ProgressReport(
                ProgressReport.STATE_SAVING_PROGRESS,
                ProgressReport.SUBSTATE_SAVING_WAV_FILE,
                _fileBeingSaved.nativePath,
                null,
                percentUploaded
        );
        dispatchEvent(new SystemStatusEvent(report));
        if (bytesPending == 0) {
            fileStream.removeEventListener(OutputProgressEvent.OUTPUT_PROGRESS, _outputListener);
            fileStream.removeEventListener(IOErrorEvent.IO_ERROR, _errorListener);
            fileStream.close();
        }
    }

    /**
     * Executed when an IOErrorEvent is fired from the FileStream instance responsible for writing the generated
     * *.wav file to disk. Redispatches information via our standardized SystemStatusEvent mechanism, and closes the
     * stream.
     * @param event
     */
    private function _doOnIoError (event : IOErrorEvent) : void {
        var fileStream : FileStream = (event.target as FileStream);
        var errorId : int = event.errorID;
        var errorText : String = event.text;
        var errorMessage : String = [errorId, errorText].join(CommonStrings.SPACE);
        var report : ProgressReport = new ProgressReport(
                ProgressReport.STATE_CANNOT_SAVE,
                ProgressReport.SUBSTATE_ERROR,
                _fileBeingSaved.nativePath,
                errorMessage
        );
        dispatchEvent(new SystemStatusEvent(report));
        fileStream.close();
        fileStream.removeEventListener(OutputProgressEvent.OUTPUT_PROGRESS, _outputListener);
        fileStream.removeEventListener(IOErrorEvent.IO_ERROR, _errorListener);
        _fileBeingSaved = null;
    }

    /**
     * Converts sound bytes from ActionScript 3 format (interleaved 32bit samples of 1 to -1 floats) to WAVE 16bit
     * format (interleaved 16bit samples of -32768 to 32767 2's-complement signed integers).
     *
     * @param   as3SoundBytes
     *          Original sound bytes, in actionscript format.
     *
     * @return  Translated sound bytes, in Wave format.
     */
    private function _toWav16Format(as3SoundBytes:ByteArray):ByteArray {
        var translatedBytes:ByteArray = new ByteArray;
        translatedBytes.endian = Endian.LITTLE_ENDIAN;
        const MAX_VAL:int = 32767;
        var originalPosition:uint = as3SoundBytes.position;
        var i:uint = 0;
        as3SoundBytes.position = 0;
        var numBytes:uint = as3SoundBytes.length;
        var originalValue:Number;
        var convertedValue:int;
        while (i < numBytes) {
            originalValue = as3SoundBytes.readFloat();
            convertedValue = ((originalValue * MAX_VAL) | 0); // same as Math.floor(), only faster
            translatedBytes.writeShort(convertedValue);
            i += SynthCommon.SAMPLE_BYTE_SIZE;
        }
        as3SoundBytes.position = originalPosition;
        translatedBytes.position = 0;
        return translatedBytes;
    }

}
}
