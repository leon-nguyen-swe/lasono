package com.lasono.track.application.port.out;

/** What the queue did with a job that failed. */
public enum FailureOutcome {
    /** The job goes back to PENDING and will be claimed again after a delay. */
    WILL_RETRY,
    /** The job ran out of attempts and is FAILED for good. */
    GAVE_UP,
    /** Another worker has taken the job over since it was claimed, so nothing was changed. */
    LEASE_LOST
}
