package com.lasono.track.application.port.out;

import java.time.Duration;
import java.util.List;
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

    /**
     * Forgets the jobs of a track that is being deleted, finished or not. The queue points at the track, so the
     * jobs have to go before the track does.
     */
    void discardJobsOf(TrackId trackId);

    /** Marks a claimed job as done, so it is never claimed again. */
    void complete(ProcessingJob job);

    /**
     * Records that an attempt failed. A job with attempts left goes back to PENDING and is not
     * claimed before {@code retryDelay} has passed; a job without attempts left becomes FAILED.
     */
    FailureOutcome fail(ProcessingJob job, String error, Duration retryDelay);

    /**
     * Gives up on jobs that are RUNNING, whose lease has expired and that have no attempts left: the
     * worker died on every attempt, so nobody will ever finish them. Marks them FAILED and returns
     * their tracks, so the caller can tell the users.
     */
    List<TrackId> failExhausted();
}
