package eu.claudius.iacob.synth.utils {
public class ProgressReport {

    // Constants most suitable for populating the `state` field.
    public static const STATE_READY_TO_RENDER:String = 'stateReadyToRender';
    public static const STATE_READY_TO_STREAM:String = 'stateReadyToStream';
    public static const STATE_READY_TO_PLAY:String = 'stateReadyToPlay';
    public static const STATE_PENDING:String = 'statePending';
    public static const STATE_STREAMING_START:String = 'stateStreamingStart';
    public static const STATE_STREAMING_PROGRESS:String = 'stateStreamingProgress';
    public static const STATE_STREAMING_DONE:String = 'stateStreamingDone';
    public static const STATE_SAVING_PROGRESS:String = 'stateSavingProgress';
    public static const STATE_PLAYING:String = 'statePlaying';
    public static const STATE_PAUSED:String = 'statePaused';
    public static const STATE_STOPPED:String = 'stateStopped';
    public static const STATE_SEEKING:String = 'stateSeeking';
    public static const STATE_CANNOT_STREAM : String = 'stateCannotStream';
    public static const STATE_CANNOT_RENDER:String = 'stateCannotRender';
    public static const STATE_CANNOT_SAVE : String = 'stateCannotSave';

    // Constants most suitable for populating the `subState` field.
    public static const SUBSTATE_LOADING_SOUNDS:String = 'substateLoadingSounds';
    public static const SUBSTATE_RENDERING_AUDIO:String = 'substateRenderingAudio';
    public static const SUBSTATE_ERROR:String = 'substateError';
    public static const SUBSTATE_NOTHING_TO_DO:String = 'substateNothingToDo';
    public static const SUBSTATE_STREAMING_IN_PROGRESS : String = 'substateStreamingInProgress';
    public static const SUBSTATE_STREAMING_CANCELLED : String = 'substateStreamingCancelled'
    public static const SUBSTATE_EMPTY_TRACKS : String = 'substateEmptyTracks';
    public static const SUBSTATE_DROPOUT : String = 'substateDropout';
    public static const SUBSTATE_END_OF_STREAM : String = 'substateEndOfStream';
    public static const SUBSTATE_SAVING_WAV_FILE : String = 'substateSavingWavFile';

    // Constants most suitable for populating the `itemState` field.
    public static const ITEM_STATE_PROGRESS:String = 'itemStateProgress';
    public static const ITEM_STATE_DONE:String = 'itemStateDone';
    public static const ITEM_STATE_ERROR:String = 'itemStateError';
    public static const ITEM_STATE_ALREADY_CACHED:String = 'itemStateAlreadyCached';

    // Misc.
    public static const ERROR_LOADING_FILES:String = 'errorLoadingFiles';
    public static const PARTIAL_LOAD_TEMPLATE:String = 'Failure loading: only loaded %s out of %s files; could not load:\n\t%s\n';
    public static const ALREADY_CACHED_TEMPLATE:String = 'All requested files were already cached (%s files were cached out of %s files requested).';

    private var _state:String;
    private var _subState:String;
    private var _item:String;
    private var _itemState:String;
    private var _itemDetail:String;
    private var _globalPercent:Number;
    private var _localPercent:Number;

    /**
     * Helper class meant to standardize status communication between the SynthProxy and the outer
     * world, but usable in other scenarios too.
     */
    public function ProgressReport(state:String = null, subState:String = null, item:String = null,
                                   itemState:String = null, globalPercent:Number = NaN,
                                   localPercent:Number = NaN) {
        _state = state;
        _subState = subState;
        _item = item;
        _itemState = itemState;
        _itemDetail = itemDetail;
        _globalPercent = globalPercent;
        _localPercent = localPercent;
    }

    /**
     * Field to use for expressing the "general", or "high-level" status of the system, e.g.:
     * a `state` of `STATE_PENDING` generally means that you cannot playback, and can be
     * used to disable the playback button, whatever might be the reason behind that.
     */
    public function get state():String {
        return _state;
    }

    public function set state(value:String):void {
        _state = value;
    }

    /**
     * Field to use for expressing the "particular", or "low-level" status of the system, e.g.:
     * a `subState` of `SUBSTATE_LOADING_SOUNDS` can be used to display the UI for monitoring
     * the sound fonts loading, whereas a `subState` of `SUBSTATE_RENDERING_AUDIO` can be used
     * to display the UI for monitoring the audio generation (aka "pre-rendering").
     */
    public function get subState():String {
        return _subState;
    }

    public function set subState(value:String):void {
        _subState = value;
    }

    /**
     * Field to use for expressing the item that should be of particular interest at a given time,
     * such as the sound font file currently being (or having been) loaded.
     */
    public function get item():String {
        return _item;
    }

    public function set item(value:String):void {
        _item = value;
    }


    /**
     * Fields to use for expressing a standardized "state" the current `item` is in, such as the
     * current sound font file being "in progress", or "loaded/done", or having suffered an "error".
     */
    public function get itemState():String {
        return _itemState;
    }

    public function set itemState(value:String):void {
        _itemState = value;
    }

    /**
     * Free-form field that could be used to add detail about the current item, such as the
     * reason why the current sound font file cannot be loaded (e.g., it could be missing or an
     * IO error could have occurred).
     */
    public function get itemDetail():String {
        return _itemDetail;
    }

    public function set itemDetail(value:String):void {
        _itemDetail = value;
    }

    /**
     * Field to use for expressing the "general", or "high-level" degree of completion of the entire process,
     * such as "to which extent" is loading the sound fonts (or the audio rendering) complete.
     */
    public function get globalPercent():Number {
        return _globalPercent;
    }

    public function set globalPercent(value:Number):void {
        _globalPercent = value;
    }

    /**
     * Field to use for expressing the ""particular", or "low-level" degree of completion of a part of the
     * entire process, such as "to which extent" is a specific sound font loaded, or a specific track
     * rendered into audio form.
     */
    public function get localPercent():Number {
        return _localPercent;
    }

    public function set localPercent(value:Number):void {
        _localPercent = value;
    }

    public function toString():String {
        return [
            '--- Progress Report ---',
            'state:' + state,
            'subState:' + subState,
            'item:' + item,
            'itemState:' + itemState,
            'itemDetail:' + itemDetail,
            'globalPercent:' + globalPercent,
            'localPercent:' + localPercent,
            '---'
        ].join('\n\t');

    }
}
}
