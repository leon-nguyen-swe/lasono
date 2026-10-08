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
        boolean leaseExpired;
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
    public void discardJobsOf(TrackId trackId) {
        jobs.removeIf(job -> job.trackId.equals(trackId));
    }

    @Override
    public Optional<ProcessingJob> claimNext(Duration lease) {
        return jobs.stream()
            .filter(job -> job.status == Status.PENDING || (isExpired(job) && job.attempts < MAX_ATTEMPTS))
            .findFirst()
            .map(job -> {
                job.status = Status.RUNNING;
                job.leaseExpired = false;
                job.attempts++;
                return new ProcessingJob(job.id, job.trackId, job.attempts, MAX_ATTEMPTS);
            });
    }

    @Override
    public void complete(ProcessingJob claimed) {
        Job job = find(claimed.id());
        if (holds(job, claimed)) {
            job.status = Status.DONE;
        }
    }

    @Override
    public FailureOutcome fail(ProcessingJob claimed, String error, Duration retryDelay) {
        Job job = find(claimed.id());
        if (!holds(job, claimed)) {
            return FailureOutcome.LEASE_LOST;
        }
        job.lastError = error;
        job.lastRetryDelay = retryDelay;
        if (job.attempts >= MAX_ATTEMPTS) {
            job.status = Status.FAILED;
            return FailureOutcome.GAVE_UP;
        }
        job.status = Status.PENDING;
        return FailureOutcome.WILL_RETRY;
    }

    /** Time does not exist here, so a test says when the leases of the running jobs have run out. */
    void expireLeases() {
        jobs.stream().filter(job -> job.status == Status.RUNNING).forEach(job -> job.leaseExpired = true);
    }

    @Override
    public List<TrackId> failExhausted() {
        List<Job> exhausted = jobs.stream()
            .filter(job -> isExpired(job) && job.attempts >= MAX_ATTEMPTS)
            .toList();
        exhausted.forEach(job -> job.status = Status.FAILED);
        return exhausted.stream().map(job -> job.trackId).toList();
    }

    /** The claiming worker still holds the job unless another worker has counted a newer attempt. */
    private static boolean holds(Job job, ProcessingJob claimed) {
        return job.status == Status.RUNNING && job.attempts == claimed.attempts();
    }

    private static boolean isExpired(Job job) {
        return job.status == Status.RUNNING && job.leaseExpired;
    }

    private Job find(UUID jobId) {
        return jobs.stream().filter(job -> job.id.equals(jobId)).findFirst().orElseThrow();
    }
}
