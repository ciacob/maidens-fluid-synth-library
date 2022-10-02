package eu.claudius.iacob.synth.utils {
public class WaveFormConfiguration {

    private var _markingsLineThickness:Number;
    private var _markingsLineColor:Number;
    private var _waveformLineThickness:Number;
    private var _waveformLineColor:Number;
    private var _waveformLineAlpha:Number;
    private var _numberOfBars:uint;
    private var _makeUpFactor:Number;

    /**
     * Sealed container to hold all the graphical properties needed for drawing a waveform representation.
     *
     * @param   markingsLineThickness
     *          Thickness of the line that marks the waveform center; the same settings are used to draw the border.
     *          Not used by `drawSimplifiedWaveForm()`.
     *
     * @param   markingsLineColor
     *          Color of the line that marks the waveform center; the same settings are used to draw the border.
     *          Not used by `drawSimplifiedWaveForm()`.
     *
     * @param   waveformLineThickness
     *          Thickness of the line that draws the actual waveform.
     *          Not used by `drawSimplifiedWaveForm()`; here, thickness of the bars is computed based on their number.
     *
     * @param   waveformLineColor
     *          Color of the line that draws the actual waveform.
     *
     * @param   waveformLineAlpha
     *          Transparency of the line that draws the actual waveform.
     *
     * @param   numberOfBars
     *          Only used by used by `drawSimplifiedWaveForm()`; controls how many vertical bars to draw, the more
     *          bars, the more accurate the drawing, but the slower the process to draw them.
     *
     * @param   makeUpFactor
     *          Only used by used by `drawSimplifiedWaveForm()`; Number to multiply all resulting bars length with;
     *          e.g., for a `makeUpFactor` of `2`, all bars' will be drawn twice as long than they normally would.
     */
    public function WaveFormConfiguration(markingsLineThickness:Number, markingsLineColor:Number,
                                          waveformLineThickness:Number, waveformLineColor:Number,
                                          waveformLineAlpha:Number, numberOfBars : uint,
                                          makeUpFactor : Number) {

        _markingsLineThickness = markingsLineThickness;
        _markingsLineColor = markingsLineColor;
        _waveformLineThickness = waveformLineThickness;
        _waveformLineColor = waveformLineColor;
        _waveformLineAlpha = waveformLineAlpha;
        _numberOfBars = numberOfBars;
        _makeUpFactor = makeUpFactor;
    }

    public function get markingsLineThickness():Number {
        return _markingsLineThickness;
    }

    public function get markingsLineColor():Number {
        return _markingsLineColor;
    }

    public function get waveformLineThickness():Number {
        return _waveformLineThickness;
    }

    public function get waveformLineColor():Number {
        return _waveformLineColor;
    }

    public function get waveformLineAlpha():Number {
        return _waveformLineAlpha;
    }

    public function get numberOfBars():uint {
        return _numberOfBars;
    }

    public function get makeUpFactor() : Number {
        return _makeUpFactor;
    }
}
}
