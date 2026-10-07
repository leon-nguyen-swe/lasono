package com.lasono.track.application.usecase;

import java.time.Duration;
import java.util.Optional;

import org.springframework.stereotype.Component;

import com.lasono.track.application.port.out.ProcessingJob;
import com.lasono.track.application.port.out.ProcessingJobQueue;
import com.lasono.track.domain.TrackRepository;

/**
 * Takes the next due processing job from the queue and runs it. A worker calls this over and over.
 */
@Component
public class RunNextProcessingJobUseCase {

    /** Longer than the FFmpeg timeout (5 minutes), so a running job is not taken by another worker. */
    private static final Duration LEASE = Duration.ofMinutes(10);

    private static final Duration RETRY_BASE_DELAY = Duration.ofSeconds(30);

    private final ProcessingJobQueue queue;
    private final ProcessTrackUseCase processTrack;
    private final TrackRepository trackRepository;

    public RunNextProcessingJobUseCase(
        ProcessingJobQueue queue,
        ProcessTrackUseCase processTrack,
        TrackRepository trackRepository
    ) {
        this.queue = queue;
        this.processTrack = processTrack;
        this.trackRepository = trackRepository;
    }

    /** Returns true when a job was taken, so the caller knows it may be worth asking again at once. */
    public boolean execute() {
        Optional<ProcessingJob> claimed = queue.claimNext(LEASE);
        if (claimed.isEmpty()) {
            return false;
        }
        ProcessingJob job = claimed.get();
        try {
            processTrack.execute(job.trackId().getValue());
            queue.complete(job.id());
        } catch (RuntimeException e) {
            queue.fail(job.id(), e.toString(), retryDelay(job.attempts()));
        }
        return true;
    }

    /** 30 seconds after the first failure, then twice as long after each next one. */
    private static Duration retryDelay(int attempts) {
        return RETRY_BASE_DELAY.multipliedBy(1L << (attempts - 1));
    }
}
