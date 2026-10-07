package com.lasono.track.application.usecase;

import java.time.Duration;
import java.util.Optional;

import org.springframework.stereotype.Component;

import com.lasono.track.application.port.out.FailureOutcome;
import com.lasono.track.application.port.out.ProcessingJob;
import com.lasono.track.application.port.out.ProcessingJobQueue;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.model.TrackStatus;

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

    /** Runs jobs until none is due and returns how many were taken. */
    public int runAllDue() {
        int taken = 0;
        while (execute()) {
            taken++;
        }
        return taken;
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
            FailureOutcome outcome = queue.fail(job.id(), e.toString(), retryDelay(job.attempts()));
            if (outcome == FailureOutcome.GAVE_UP) {
                markTrackFailed(job.trackId());
            }
        }
        return true;
    }

    /**
     * No retry is left, so the user must see that this track will never be playable. A track that is
     * already READY stays READY: the audio was processed, only reporting the job as done kept failing.
     */
    private void markTrackFailed(TrackId trackId) {
        trackRepository.findById(trackId)
            .filter(track -> track.getStatus() == TrackStatus.PROCESSING)
            .ifPresent(track -> {
                track.startProcessing();
                track.processingFailed();
                trackRepository.save(track);
            });
    }

    /** 30 seconds after the first failure, then twice as long after each next one. */
    private static Duration retryDelay(int attempts) {
        return RETRY_BASE_DELAY.multipliedBy(1L << (attempts - 1));
    }
}
