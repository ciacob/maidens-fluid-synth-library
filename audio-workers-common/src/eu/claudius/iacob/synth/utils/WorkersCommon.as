package eu.claudius.iacob.synth.utils {
public class WorkersCommon {
    public function WorkersCommon() {
    }

    public static const WORKER_OWN_ID:String = '$workerOwnId';
    public static const SESSION_ID:String = '$sessionId';

    public static const IN_CHANNEL_PREFIX:String = '$inChannelPrefix';
    public static const INPUT_TRACKS:String = '$inputTracks';

    public static const OUT_CHANNEL_PREFIX:String = '$outChannelPrefix';
    public static const OUTPUT_BYTES:String = '$outputBytes';

    public static const COMMAND_NAME:String = '$commandName';
    public static const COMMAND_PAYLOAD:String = '$commandPayload';
    public static const COMMAND_START_WORKER : String = '$startWorker';
    public static const COMMAND_SETUP_WORKER:String = '$setupWorker';
    public static const COMMAND_EXECUTE_WORKER:String = '$executeWorker';
    public static const COMMAND_RELEASE_LISTENER:String = '$releaseListener';
    public static const COMMAND_DONE:String = '$commandDone';

    public static const REPORT_NAME:String = '$reportName';
    public static const REPORT_COMMAND_REJECTED:String = '$commandRejected';
    public static const REJECTION_REASON:String = '$rejectionReason';
    public static const REASON_RENDERING_IN_PROGRESS:String = 'renderingInProgress';
    public static const REASON_WORKER_NOT_RUNNING:String = 'workerNotRunning';

    public static const COMMAND_EXECUTION_ERROR:String = '$commandExecutionError';
    public static const ERROR_BAD_WORKER_SETUP:String = 'badWorkerSetup';
    public static const EXECUTION_ERROR_ID:String = '$executionErrorId';
    public static const EXECUTION_ERROR_MESSAGE:String = '$executionErrorMessage';

    public static const SOUNDS_ASSIGNMENT_MAP:String = '$soundsAssignmentMap';
    public static const SOUND_BYTES:String = '$soundBytes';

    public static const RENDER_COMPLETE:String = 'renderComplete';
    public static const WORKER_STARTED:String = 'workerRunning';
}
}
