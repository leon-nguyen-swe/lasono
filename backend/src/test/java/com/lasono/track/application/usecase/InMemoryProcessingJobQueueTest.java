package com.lasono.track.application.usecase;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.util.UUID;

import org.junit.jupiter.api.Test;

import com.lasono.track.application.port.out.FailureOutcome;
import com.lasono.track.application.port.out.ProcessingJob;
import com.lasono.track.domain.TrackId;

class InMemoryProcessingJobQueueTest {

    private static final Duration LEASE = Duration.ofMinutes(5);
    private static final Duration DELAY = Duration.ofSeconds(30);

    private final InMemoryProcessingJobQueue queue = new InMemoryProcessingJobQueue();
    private final TrackId trackId = new TrackId(UUID.randomUUID());

    @Test
    void claimsAQueuedJobOnceAndCountsTheAttempt() {
        queue.enqueue(trackId);

        ProcessingJob job = queue.claimNext(LEASE).orElseThrow();

        assertThat(job.trackId()).isEqualTo(trackId);
        assertThat(job.attempts()).isEqualTo(1);
        assertThat(queue.claimNext(LEASE)).as("a running job is not claimed again").isEmpty();
    }

    @Test
    void doneJobsAreNeverClaimedAgain() {
        queue.enqueue(trackId);
        ProcessingJob job = queue.claimNext(LEASE).orElseThrow();

        queue.complete(job.id());

        assertThat(queue.claimNext(LEASE)).isEmpty();
    }

    @Test
    void aFailedJobIsRetriedUntilItRunsOutOfAttempts() {
        queue.enqueue(trackId);

        for (int attempt = 1; attempt < InMemoryProcessingJobQueue.MAX_ATTEMPTS; attempt++) {
            ProcessingJob job = queue.claimNext(LEASE).orElseThrow();
            assertThat(queue.fail(job.id(), "boom", DELAY)).isEqualTo(FailureOutcome.WILL_RETRY);
        }
        ProcessingJob last = queue.claimNext(LEASE).orElseThrow();

        assertThat(last.attempts()).isEqualTo(InMemoryProcessingJobQueue.MAX_ATTEMPTS);
        assertThat(queue.fail(last.id(), "boom", DELAY)).isEqualTo(FailureOutcome.GAVE_UP);
        assertThat(queue.claimNext(LEASE)).isEmpty();
    }
}
