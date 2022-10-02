package eu.claudius.iacob.synth.utils {
public class AnalysisResult {

    private var _canEngagePlayback:Boolean;

    private var _shouldIncreaseBuffer:Boolean;

    private var _suggestedBufferIncreaseFactor:Number;

    private var _shouldAddWorker:Boolean;

    private var _avgRenderingSpeed:Number;

    public function AnalysisResult(avgRenderingSpeed:Number, canEngagePlayback:Boolean,
                                   shouldIncreaseBuffer:Boolean, suggestedBufferIncreaseFactor:Number,
                                   shouldAddWorker:Boolean) {

        _avgRenderingSpeed = avgRenderingSpeed;
        _canEngagePlayback = canEngagePlayback;
        _shouldIncreaseBuffer = shouldIncreaseBuffer;
        _suggestedBufferIncreaseFactor = suggestedBufferIncreaseFactor;
        _shouldAddWorker = shouldAddWorker;
    }

    public function get canEngagePlayback():Boolean {
        return _canEngagePlayback;
    }

    public function get shouldIncreaseBuffer():Boolean {
        return _shouldIncreaseBuffer;
    }

    public function get suggestedBufferIncreaseFactor():Number {
        return _suggestedBufferIncreaseFactor;
    }

    public function get shouldAddWorker():Boolean {
        return _shouldAddWorker;
    }

    public function get avgRenderingSpeed():Number {
        return _avgRenderingSpeed;
    }

    public function toString():String {
        return 'AnalysisResult instance:\n' + JSON.stringify({
            'canEngagePlayback': _canEngagePlayback,
            'shouldIncreaseBuffer': _shouldIncreaseBuffer,
            'suggestedBufferIncreaseFactor': _suggestedBufferIncreaseFactor,
            'shouldAddWorker': _shouldAddWorker,
            'avgRenderingSpeed': _avgRenderingSpeed
        }, null, '\t');
    }
}
}
