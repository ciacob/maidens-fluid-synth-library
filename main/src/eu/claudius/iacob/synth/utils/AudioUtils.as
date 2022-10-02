package eu.claudius.iacob.synth.utils {
import eu.claudius.iacob.synth.constants.SynthCommon;

import flash.utils.ByteArray;
import flash.utils.Endian;

/**
 * General-purpose class with ready to use utilities for managing audio.
 */
public class AudioUtils {

    private static var _recyclableSampleStorages:Array = [];

    public function AudioUtils() {
    }

    /**
     * Creates and returns a audio samples-compatible ByteArray.
     */
    public static function makeSamplesStorage():ByteArray {
        if (_recyclableSampleStorages.length > 0) {
            return _recyclableSampleStorages.pop();
        }
        var storage:ByteArray = new ByteArray();
        storage.endian = Endian.LITTLE_ENDIAN;
        return storage;
    }

    /**
     * Clears and sets for later reuse the given `storage` ByteArray. The idea behind this mechanism is that it might
     * consume more CPU to create and garbage collect ByteArrays that to reuse them if possible.
     *
     * @param   storage
     *          A "little endian" ByteArray to reuse.
     */
    public static function recycleSamplesStorage(storage:ByteArray):void {
        storage.clear();
        _recyclableSampleStorages.push(storage);
    }

    /**
     * Normalizes in-place all floats (32 bit numbers) found in given `samplesBuffer` ByteArray, trying
     * to get the highest peak as close as possible to `1` (with respect to the SAFETY_THRESHOLD
     * constant). No value is returned, the original ByteArray is modified.
     *
     * @param   soundBytes
     *          A ByteArray containing floats (32 bit floating point numbers), typically between `1` (maximum waveform
     *          positive peak) and `-1` (maximum waveform negative peak). The DC-current level (completely silent
     *          waveform) is represented as `0`.
     *
     * @param   normalizeInPlace
     *          Optional; whether to change the provided `samplesBuffer` ByteArray (`true`, the default) or to return a
     *          new ByteArray with the changes applied (`false`).
     *
     * @return  Based on the value of the `normalizeInPlace` argument, returns a copy of the provided `samplesBuffer`,
     *          with all the changes applied (when `normalizeInPlace` is `false`) or `null` (when `normalizeInPlace` is
     *          `true`, the default).
     */
    public static function normalizeValues(soundBytes:ByteArray, normalizeInPlace : Boolean = true) : ByteArray {
        var sampleSize:int = SynthCommon.SAMPLE_BYTE_SIZE;

        // Find min, max and max peak
        var sample:Number;
        var maxValue:Number = 0;
        var originalPosition:uint = soundBytes.position;
        soundBytes.position = 0;
        var numBytesInBuffer:uint = soundBytes.bytesAvailable;
        while (numBytesInBuffer > 0) {
            sample = Math.abs(soundBytes.readFloat());
            if (sample > maxValue) {
                maxValue = sample;
            }
            numBytesInBuffer -= sampleSize;
        }

        // Normalize samples
        var outputBytes : ByteArray;
        if (!normalizeInPlace) {
            outputBytes = makeSamplesStorage();
        }
        var normalizeFactor:Number = (SynthCommon.CEIL_LEVEL / maxValue);
        var positionBeforeRead:Number = 0;
        soundBytes.position = 0;
        numBytesInBuffer = soundBytes.bytesAvailable;
        while (numBytesInBuffer > 0) {
            positionBeforeRead = soundBytes.position;
            sample = soundBytes.readFloat();
            sample *= normalizeFactor;
            if (normalizeInPlace) {
                soundBytes.position = positionBeforeRead;
                soundBytes.writeFloat(sample);
            } else {
                outputBytes.writeFloat(sample);
            }
            numBytesInBuffer -= sampleSize;
        }
        soundBytes.position = originalPosition;
        if (!normalizeInPlace) {
            outputBytes.position = 0;
        }
        return normalizeInPlace? null : outputBytes;
    }

}
}
