package eu.claudius.iacob.synth.utils {
import eu.claudius.iacob.synth.constants.SynthCommon;

import flash.display.BitmapData;
import flash.display.CapsStyle;
import flash.display.Graphics;
import flash.display.JointStyle;
import flash.display.LineScaleMode;
import flash.display.Sprite;
import flash.utils.ByteArray;

/**
 * General purpose class with static methods that deal with graphical tasks, such as drawing a waveform rendition of
 * the rendered material.
 */
public class AudioGraphics {

    private static const MARKINGS_LINE_THICKNESS:Number = 1;
    private static const MARKINGS_LINE_COLOR:Number = 0xc0c0c0;
    private static const WAVEFORM_LINE_THICKNESS:Number = 0.5;
    private static const WAVEFORM_LINE_COLOR:Number = 0x3366ff;
    private static const WAVEFORM_LINE_ALPHA:Number = 0.8;
    private static const NUMBER_OF_BARS:uint = 1000;
    private static const MAKEUP_FACTOR:Number = 1;
    private static const DEFAULT_WAVEFORM_CONFIG:WaveFormConfiguration = new WaveFormConfiguration(
            MARKINGS_LINE_THICKNESS,
            MARKINGS_LINE_COLOR,
            WAVEFORM_LINE_THICKNESS,
            WAVEFORM_LINE_COLOR,
            WAVEFORM_LINE_ALPHA,
            NUMBER_OF_BARS,
            MAKEUP_FACTOR
    );

    private static var _tmpCanvas:Sprite;
    private static var srcBitmapData:BitmapData;

    public function AudioGraphics() {
    }

    /**
     * Draws a rendition of the waveform described by given "samples" inside the provided "canvas"
     * UIComponent. The waveform is fitted horizontally and trimmed vertically.
     *
     * @param   samples
     *          ByteArray with samples describing the waveform to be drawn (mono signal expected).
     *
     * @param   canvas
     *          Sprite (or subclass) instance to draw inside. Its width and height will limit the waveform being drawn.
     *
     * @param   config
     *          Optional. A WaveFormConfiguration instance holding properties that control how the resulting waveform
     *          will look like. For all properties not given there, defaults will be assumed.
     */
    public static function drawWaveForm(samples:ByteArray, canvas:Sprite, config:WaveFormConfiguration = null):void {
        if (canvas && canvas.graphics) {

            // Store the original position inside the samples storage we draw from in order to restore it later.
            var originalPosition:uint = samples.position;

            // Ensure proper defaults for all drawing parameters.
            config = (config || DEFAULT_WAVEFORM_CONFIG);
            var markingsLineThickness:Number = config.markingsLineThickness;
            var markingsLineColor:Number = config.markingsLineColor;
            var waveformLineThickness:Number = config.waveformLineThickness;
            var waveformLineColor:Number = config.waveformLineColor;
            var waveformLineAlpha:Number = config.waveformLineAlpha;

            // Draw into a temporary Sprite; we will only use its bitmap rendition, not the actual vector drawn, which
            // would likely be a path with millions of overlapping nodes nobody would actually see anyway.
            _tmpCanvas = (_tmpCanvas || new Sprite);
            var tmpG:Graphics = _tmpCanvas.graphics;
            tmpG.clear();
            if (samples && samples.length > 0) {
                var numSamples:Number = (samples.length / SynthCommon.SAMPLE_BYTE_SIZE);
                var availableH:Number = canvas.height;
                var availableW:Number = canvas.width;
                var halfH:Number = (availableH * 0.5);

                // Draw markings
                tmpG.lineStyle(markingsLineThickness, markingsLineColor);
                var mR:Number = (availableW - markingsLineThickness);
                var mB:Number = (availableH - markingsLineThickness);
                var mM:Number = (halfH - markingsLineThickness);
                tmpG.moveTo(0, 0);
                tmpG.lineTo(mR, 0);
                tmpG.lineTo(mR, mB);
                tmpG.lineTo(0, mB);
                tmpG.lineTo(0, 0);
                tmpG.moveTo(0, mM);
                tmpG.lineTo(mR, mM);

                // Draw waveform
                tmpG.lineStyle(waveformLineThickness, waveformLineColor, waveformLineAlpha);
                tmpG.moveTo(0, mM);
                samples.position = 0;
                var currSampleIndex:Number = 0;
                var maxIndex:Number = (numSamples - 1);
                var sample:Number;
                while (samples.bytesAvailable) {
                    sample = samples.readFloat();
                    var sampleHeightPerc:Number = sample;
                    if (sampleHeightPerc < -1) {
                        sampleHeightPerc = -1;
                    }
                    if (sampleHeightPerc > 1) {
                        sampleHeightPerc = 1;
                    }
                    var sampleY:Number = (halfH - waveformLineThickness - sampleHeightPerc *
                            (halfH - waveformLineThickness));
                    var sampleX:Number = (currSampleIndex / maxIndex) * (availableW - waveformLineThickness);
                    tmpG.lineTo(sampleX, sampleY);
                    currSampleIndex++;
                }
            }

            // Transfer a bitmap rendition of the drawn vector from the temporary Sprite to our target Sprite.
            if (srcBitmapData) {
                srcBitmapData.dispose();
                srcBitmapData = null;
            }
            srcBitmapData = new BitmapData(canvas.width, canvas.height);
            srcBitmapData.draw(_tmpCanvas);
            canvas.cacheAsBitmap = true;
            var g:Graphics = canvas.graphics;
            g.beginBitmapFill(srcBitmapData, null, false);
            g.drawRect(0, 0, srcBitmapData.width, srcBitmapData.height);

            // Restore the position inside the samples storage we read from.
            samples.position = originalPosition;
        }
    }

    /**
     * Draws a rendition of the waveform described by given "samples" inside the provided "canvas"
     * UIComponent. The waveform is fitted horizontally and trimmed vertically. Less accurate than drawWaveForm, but
     * about 100 times faster.
     *
     * @param   samples
     *          ByteArray with samples describing the waveform to be drawn (mono signal expected).
     *
     * @param   canvas
     *          Sprite (or subclass) instance to draw inside. Its width and height will limit the waveform being drawn.
     *
     * @param   config
     *          Optional. A WaveFormConfiguration instance holding properties that control how the resulting waveform
     *          will look like. For all properties not given there, defaults will be assumed.
     */
    public static function drawSimplifiedWaveForm (samples : ByteArray, canvas : Sprite,
                                                   config:WaveFormConfiguration = null) : void {

        // Store the original position inside the samples storage we draw from in order to restore it later.
        var originalPosition:uint = samples.position;

        // Ensure proper defaults for all drawing parameters.
        config = (config || DEFAULT_WAVEFORM_CONFIG);

        var barColor:Number = config.waveformLineColor;
        var barAlpha:Number = config.waveformLineAlpha;
        var numBars : uint = config.numberOfBars;

        // Compute `numBars` values out of the provided `samples` ByteArray.
        var sampleSize : int = SynthCommon.SAMPLE_BYTE_SIZE;
        var barValues : Array = [];
        var numSamples:uint = Math.floor (samples.length / sampleSize);
        var samplesPerBar : uint = Math.floor (numSamples / numBars);
        var barIndex : int = 0;
        var sampleIndex : uint;
        var byteIndex : uint;
        var sampleValue : Number;
        var makeUpFactor : Number = isNaN(config.makeUpFactor)? 1 : config.makeUpFactor;
        for (barIndex; barIndex < numBars; barIndex++) {
            sampleIndex = barIndex * samplesPerBar;
            byteIndex = (sampleIndex * sampleSize);
            samples.position = byteIndex;
            if (samples.bytesAvailable >= sampleSize) {
                sampleValue = Math.abs(samples.readFloat());
                barValues[barIndex] = Math.min(1, sampleValue * makeUpFactor);
            } else {
                barValues[barIndex] = 0;
            }
        }

        // Draw bars that approximate the audio data sampled.
        var barValue : Number;
        var availableW:Number = canvas.width;
        var availableH:Number = canvas.height;
        var barZoneW : Number = (availableW / numBars);
        var barW : Number = (barZoneW * 0.5);
        var gutterW : Number = (barW * 0.5);
        var barX : Number;
        var barStartY : Number = availableH;
        var barEndY : Number;
        var barH : Number;
        var g : Graphics = canvas.graphics;
        g.clear();
        g.lineStyle(barW, barColor, barAlpha, true, LineScaleMode.NORMAL, CapsStyle.NONE, JointStyle.ROUND);
        for (barIndex = 0; barIndex < numBars; barIndex++) {
            barValue = (barValues[barIndex] as Number);
            barX = (barIndex * barZoneW + gutterW);
            barH = Math.max(1, availableH * barValue);
            barEndY = (barStartY - barH);
            g.moveTo(barX, barStartY);
            g.lineTo(barX, barEndY);
        }

        // Restore the position inside the samples storage we read from.
        samples.position = originalPosition;
    }
}
}
