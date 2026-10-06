package com.lasono.track.application.port.out;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

import com.lasono.track.domain.TrackId;

public interface ProcessingJobQueue {

    /** Adds a job that asks a worker to process the audio of {@code trackId}. */
    void enqueue(TrackId trackId);

    /**
     * Claims the next job that is due: marks it RUNNING, counts the attempt, and leases it for
     * {@code lease}. Returns empty when no job is due.
     */
    Optional<ProcessingJob> claimNext(Duration lease);

    /** Marks a claimed job as done, so it is never claimed again. */
    void complete(UUID jobId);

    /**
     * Records that an attempt failed. A job with attempts left goes back to PENDING and is not
     * claimed before {@code retryDelay} has passed; a job without attempts left becomes FAILED.
     */
    FailureOutcome fail(UUID jobId, String error, Duration retryDelay);
}
