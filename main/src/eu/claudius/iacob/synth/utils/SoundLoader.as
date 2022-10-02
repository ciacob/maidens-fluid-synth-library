package eu.claudius.iacob.synth.utils {
import eu.claudius.iacob.synth.events.SystemStatusEvent;

import flash.events.Event;
import flash.events.EventDispatcher;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.filesystem.File;
import flash.filesystem.FileMode;
import flash.filesystem.FileStream;
import flash.utils.ByteArray;

import ro.ciacob.utils.Strings;

/**
 * Helper class that loads sound font files base on a given list of GM patch numbers (aka "presets"). The files are
 * located based on a given home folder and extension (their name, otherwise, should be the preset number). Once
 * located, the files are asynchronously loaded into an internal cache, while the client code is informed on the
 * progress via SystemStatusEvent dispatches. The cache itself can e retrieved via the `sounds` getter.
 */
public class SoundLoader extends EventDispatcher {

    public static const SOUND_FILES_HOME:String = 'assets/sounds';
    public static const SOUND_FILES_EXTENSION:String = '.sf2';

    private var _soundsCache:Object;
    private var _presets:Vector.<PresetDescriptor>
    private var _soundFilesHome:String = SOUND_FILES_HOME;
    private var _soundFilesExtension:String = SOUND_FILES_EXTENSION;
    private var _presetNumber:uint = 0;
    private var _presetLabel:String = null;
    private var _duePresets:uint = 0;
    private var _numPresetsToLoad:uint = 0;
    private var _numPresetsLoaded:uint = 0;
    private var _numCachedPresetsSkipped:uint = 0;
    private var _failedFilePaths:Array = [];
    private var _fileStream:FileStream;
    private var _soundFontsPath:String;


    /**
     * @constructor
     */
    public function SoundLoader() {
        _soundsCache = {};
    }

    /**
     * Asynchronously loads the sound font files corresponding to given `presets`, and internally caches the resulting
     * ByteArrays. Reports back on the progress via system status events. When the entire process is done, the cache can
     * be externally retrieved, via the `sounds` getter.
     *
     * @param       presets
     *              A Vector with PresetDescriptor instances, each containing the preset number and an associated name.
     *
     * @param       soundFilesHome
     *              Relative path to the folder where *.sf2 files are expected to live. Optional; if not given, defaults
     *              to the value of the `SOUND_FILES_HOME` constant.
     *
     * @param       soundFilesExtension
     *              Extension the files containing sound samples are expecting to have. Optional, if not given, defaults
     *              to the value of the `SOUND_FILES_EXTENSION` constant.
     *
     * @dispatch    Causes a SystemStatusEvent to be dispatched when any of the following occurs:
     *              - there is progress in loading a *.sf2 file;
     *              - a *.sf2 has been completely loaded and cached;
     *              - all suitable *.sf2 files have been completely loaded and cached;
     *              - a *.sf2 file is missing;
     *              - a *.sf2 file cannot be loaded for reasons other than the file missing from disk.
     *              The `report` property of the dispatched SystemStatusEvent will contain a ProgressReport instance with
     *              details.
     */
    public function preloadSounds(presets:Vector.<PresetDescriptor>,
                                  soundFilesHome:String = null,
                                  soundFilesExtension:String = null):void {
        _reset();

        // Process and store the arguments.
        _presets = presets;
        if (soundFilesHome != null) {
            _soundFilesHome = soundFilesHome;
        }
        if (soundFilesExtension != null) {
            _soundFilesExtension = soundFilesExtension;
        }

        // Start the process.
        _duePresets = presets.length;
        _numPresetsToLoad = presets.length;
        _loadNextPreset();
    }

    /**
     * The sound files loaded so far, as an Object containing ByteArray instances (with each ByteArray containing the
     * bytes loaded from a sound font file).
     * The ByteArrays are indexed based on the General MIDI patch number that represents the musical instrument
     * emulation inside the loaded sound font file. E.g., the samples for a Violin sound would reside in a file called
     * "40.sf2" (the file must not contain other sounds), and would be loaded in a ByteArray that gets stored under
     * index `40` in the sounds cache Object: that is because, in the GM specification, Violin has patch number 40.
     */
    public function get sounds():Object {
        return _soundsCache;
    }

    /**
     * Set internal flags to their initial value, so that loading a new set of preset descriptors is possible.
     */
    private function _reset():void {
        _presetNumber = 0;
        _presetLabel = null;
        _duePresets = 0;
        _numPresetsToLoad = 0;
        _numPresetsLoaded = 0;
        _numCachedPresetsSkipped = 0;
        _failedFilePaths = [];
        _soundFontsPath = null;
    }

    /**
     * Dispatches received `report` inside a SystemStatusEvent.
     * @param report
     */
    private function _broadcastReport(report:ProgressReport):void {
        dispatchEvent(new SystemStatusEvent(report));
    }


    /**
     * Executed when the entire process is complete. Compiles and broadcasts a specific status report.
     */
    private function _reportAllDone():void {
        var progress:ProgressReport = new ProgressReport;
        progress.state = ProgressReport.STATE_READY_TO_RENDER;
        progress.globalPercent = 1;
        _broadcastReport(progress);
    }

    /**
     * Executed when all received presets have already been dealt with in previous loading sessions, so that their
     * respective ByteArrays are already cached. Compiles and broadcasts a specific status report.
     */
    private function _reportNothingToDo():void {
        var progress:ProgressReport = new ProgressReport;
        progress.state = ProgressReport.STATE_READY_TO_RENDER;
        progress.subState = ProgressReport.SUBSTATE_NOTHING_TO_DO;
        progress.itemState = ProgressReport.ITEM_STATE_ALREADY_CACHED;
        progress.itemDetail = Strings.sprintf(ProgressReport.ALREADY_CACHED_TEMPLATE, _numCachedPresetsSkipped,
                _duePresets);
        progress.globalPercent = 1;
        _broadcastReport(progress);
    }

    /**
     * Executed when the process completes, but all received presets were not successfully handled. Compiles and
     * broadcasts a specific status report, which includes a detailed list of all failures.
     */
    private function _reportAllFailed():void {
        var progress:ProgressReport = new ProgressReport;
        progress.state = ProgressReport.STATE_CANNOT_RENDER;
        progress.subState = ProgressReport.SUBSTATE_ERROR;
        progress.item = ProgressReport.ERROR_LOADING_FILES;
        progress.itemState = ProgressReport.ITEM_STATE_ERROR;
        progress.itemDetail = Strings.sprintf(ProgressReport.PARTIAL_LOAD_TEMPLATE, _numPresetsLoaded, _duePresets, _failedFilePaths.join(',\n\t'));
        progress.localPercent = (_numPresetsLoaded / _duePresets);
        progress.globalPercent = 1;
        _broadcastReport(progress);
    }

    /**
     * Executed when one, individual preset is successfully resolved to a ByteArray (and that is successfully cached).
     * Compiles and broadcasts a specific status report, which includes a global percent value (which could be used to
     * display a primary progress bar to the end-user).
     */
    private function _reportPresetDone():void {
        var progress:ProgressReport = new ProgressReport;
        progress.state = ProgressReport.STATE_PENDING;
        progress.subState = ProgressReport.SUBSTATE_LOADING_SOUNDS;
        progress.item = _soundFontsPath;
        progress.itemState = ProgressReport.ITEM_STATE_DONE;
        progress.itemDetail = _presetLabel;
        var globalPercent:Number = ((_duePresets - _numPresetsToLoad) / _duePresets);
        progress.globalPercent = globalPercent;
        _broadcastReport(progress);
    }

    /**
     * Executed while an individual sound file is being loaded from disk. Compiles and broadcasts a specific status
     * report, which includes a local percent value (which could be used to display a secondary progress bar to the
     * end-user).
     *
     * @param   percentLoaded
     *          The local percent to report.
     */
    private function _reportFileProgress(percentLoaded:Number):void {
        var progress:ProgressReport = new ProgressReport;
        progress.state = ProgressReport.STATE_PENDING;
        progress.subState = ProgressReport.SUBSTATE_LOADING_SOUNDS;
        progress.item = _soundFontsPath;
        progress.itemState = ProgressReport.ITEM_STATE_PROGRESS;
        progress.itemDetail = _presetLabel;
        var globalPercent:Number = ((_duePresets - _numPresetsToLoad) / _duePresets);
        progress.globalPercent = globalPercent;
        progress.localPercent = percentLoaded;
        _broadcastReport(progress);
    }

    /**
     * Executed when the sound file for a requested preset cannot be located (or accessed) on disk. Compiles and
     * broadcasts a specific status report with details.
     */
    private function _reportMissingFile():void {
        var progress:ProgressReport = new ProgressReport;
        progress.state = ProgressReport.STATE_PENDING;
        progress.subState = ProgressReport.SUBSTATE_LOADING_SOUNDS;
        progress.item = _soundFontsPath;
        progress.itemState = ProgressReport.ITEM_STATE_ERROR;
        progress.itemDetail = 'File is missing or not accessible.';
        _broadcastReport(progress);
    }

    /**
     * Executed when a low level error occurs while reading a sound file from disk. Compiles and broadcasts a specific
     * status report with details.
     *
     * @param   errorID
     *          Numeric error id to report.
     *
     * @param   errorText
     *          Textual error description to report.
     */
    private function _reportIoError(errorID:int, errorText:String):void {
        var progress:ProgressReport = new ProgressReport;
        progress.state = ProgressReport.STATE_PENDING;
        progress.subState = ProgressReport.SUBSTATE_LOADING_SOUNDS;
        progress.item = _soundFontsPath;
        progress.itemState = ProgressReport.ITEM_STATE_ERROR;
        progress.itemDetail = (errorID + ': ' + errorText);
        _broadcastReport(progress);
    }

    /**
     * Event listener to respond to an `Event.COMPLETE` event.
     * @param event
     */
    private function _onFileLoaded(event:Event):void {
        var storage:ByteArray = new ByteArray;
        _fileStream.readBytes(storage, 0, _fileStream.bytesAvailable);
        _soundsCache[_presetNumber] = storage;
        _fileStream.close();
        _fileStream = null;
        _numPresetsToLoad -= 1;
        _numPresetsLoaded++;
        _reportPresetDone();
        _loadNextPreset();
    }

    /**
     * Event listener to respond to an `IOErrorEvent.IO_ERROR` event.
     * @param event
     */
    private function _onFileIoError(event:IOErrorEvent):void {
        _soundsCache[_presetNumber] = null;
        _numPresetsToLoad -= 1;
        _failedFilePaths.push(_soundFontsPath);
        _reportIoError(event.errorID, event.text);
    }

    /**
     * Event listener to respond to an `ProgressEvent.PROGRESS` event.
     * @param event
     */
    private function _onFileProgress(event:ProgressEvent):void {
        _reportFileProgress(event.bytesLoaded / event.bytesTotal);
    }

    /**
     * Main class routine; loads the next available preset in the list of registered presets, omitting those that have
     * been dealt with already. Causes several reports to be broadcasted in the process.
     */
    private function _loadNextPreset():void {
        var preset:PresetDescriptor;

        // Skip through the presets that were already loaded
        while (_numPresetsToLoad > 0 && ((_presetNumber = (preset = _presets.shift()).number) in _soundsCache)) {
            _numPresetsToLoad -= 1;
            _duePresets -= 1;
            _numCachedPresetsSkipped++;
        }

        // If we have one preset that was not loaded already, start loading it.
        if (_numPresetsToLoad > 0) {
            _presetLabel = preset.label;
            var soundFontsFile:File = File.applicationDirectory
                    .resolvePath(_soundFilesHome)
                    .resolvePath(_presetNumber + _soundFilesExtension);
            _soundFontsPath = soundFontsFile.nativePath;

            // Skip presets with missing *.sf2 files.
            if (!soundFontsFile.exists) {
                _soundsCache[_presetNumber] = null;
                _numPresetsToLoad -= 1;
                _failedFilePaths.push(_soundFontsPath);
                _reportMissingFile();
                _loadNextPreset();
                return;
            }

            // Load the file if found.
            _fileStream = new FileStream;
            _fileStream.addEventListener(Event.COMPLETE, _onFileLoaded);
            _fileStream.addEventListener(ProgressEvent.PROGRESS, _onFileProgress);
            _fileStream.addEventListener(IOErrorEvent.IO_ERROR, _onFileIoError);
            _fileStream.openAsync(soundFontsFile, FileMode.READ);
        }

        // Otherwise, report the end of the process
        else {
            if (_numPresetsLoaded == _duePresets) {
                _reportAllDone();
            } else if (_numCachedPresetsSkipped == _duePresets) {
                _reportNothingToDo();
            } else {
                _reportAllFailed();
            }
        }
    }

}
}
