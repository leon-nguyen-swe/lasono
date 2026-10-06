package com.lasono.track.application.port.out;

import java.time.Duration;
import java.util.Optional;

import com.lasono.track.domain.TrackId;

public interface ProcessingJobQueue {

    /** Adds a job that asks a worker to process the audio of {@code trackId}. */
    void enqueue(TrackId trackId);

    /**
     * Claims the next job that is due: marks it RUNNING, counts the attempt, and leases it for
     * {@code lease}. Returns empty when no job is due.
     */
    Optional<ProcessingJob> claimNext(Duration lease);
}
