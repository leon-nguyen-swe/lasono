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

/**
 * Behaves like the real queue without a database: a job is claimed once per attempt and is retried
 * until it has used {@link #MAX_ATTEMPTS}. Time does not exist here, so a retry delay is only recorded.
 */
class InMemoryProcessingJobQueue implements ProcessingJobQueue {

    static final int MAX_ATTEMPTS = 3;

    enum Status { PENDING, RUNNING, DONE, FAILED }

    static final class Job {
        final UUID id = UUID.randomUUID();
        final TrackId trackId;
        Status status = Status.PENDING;
        int attempts;
        String lastError;
        Duration lastRetryDelay;

        Job(TrackId trackId) {
            this.trackId = trackId;
        }
    }

    final List<TrackId> enqueued = new ArrayList<>();
    final List<Job> jobs = new ArrayList<>();
    /** When set, {@link #enqueue} throws it instead of queueing. */
    RuntimeException enqueueFailure;

    @Override
    public void enqueue(TrackId trackId) {
        if (enqueueFailure != null) {
            throw enqueueFailure;
        }
        enqueued.add(trackId);
        jobs.add(new Job(trackId));
    }

    @Override
    public Optional<ProcessingJob> claimNext(Duration lease) {
        return jobs.stream()
            .filter(job -> job.status == Status.PENDING)
            .findFirst()
            .map(job -> {
                job.status = Status.RUNNING;
                job.attempts++;
                return new ProcessingJob(job.id, job.trackId, job.attempts, MAX_ATTEMPTS);
            });
    }

    @Override
    public void complete(UUID jobId) {
        find(jobId).status = Status.DONE;
    }

    @Override
    public FailureOutcome fail(UUID jobId, String error, Duration retryDelay) {
        Job job = find(jobId);
        job.lastError = error;
        job.lastRetryDelay = retryDelay;
        if (job.attempts >= MAX_ATTEMPTS) {
            job.status = Status.FAILED;
            return FailureOutcome.GAVE_UP;
        }
        job.status = Status.PENDING;
        return FailureOutcome.WILL_RETRY;
    }

    @Override
    public List<TrackId> failExhausted() {
        return List.of();
    }

    private Job find(UUID jobId) {
        return jobs.stream().filter(job -> job.id.equals(jobId)).findFirst().orElseThrow();
    }
}
