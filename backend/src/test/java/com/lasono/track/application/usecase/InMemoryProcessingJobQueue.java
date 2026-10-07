package com.lasono.track.application.usecase;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import com.lasono.track.application.port.out.FailureOutcome;
import com.lasono.track.application.port.out.ProcessingJob;
import com.lasono.track.application.port.out.ProcessingJobQueue;
import com.lasono.track.domain.TrackId;

/** Remembers the tracks that were queued. Claiming and finishing jobs is not needed by any test yet. */
class InMemoryProcessingJobQueue implements ProcessingJobQueue {

    final List<TrackId> enqueued = new ArrayList<>();

    @Override
    public void enqueue(TrackId trackId) {
        enqueued.add(trackId);
    }

    @Override
    public Optional<ProcessingJob> claimNext(Duration lease) {
        throw new UnsupportedOperationException("not needed yet");
    }

    @Override
    public void complete(UUID jobId) {
        throw new UnsupportedOperationException("not needed yet");
    }

    @Override
    public FailureOutcome fail(UUID jobId, String error, Duration retryDelay) {
        throw new UnsupportedOperationException("not needed yet");
    }
}
