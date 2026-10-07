package com.lasono.track.infrastructure.processing;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import com.lasono.track.application.usecase.RunNextProcessingJobUseCase;

/**
 * The background worker: every few seconds it runs the processing jobs that are due. It is on by
 * default and can be switched off with {@code lasono.processing.worker-enabled=false}, for example
 * in tests that must not have a thread taking jobs behind their back.
 *
 * <p>If a run throws (say the database is down), Spring logs the error and the schedule goes on, so
 * the next poll tries again.
 */
@Component
@EnableScheduling
@ConditionalOnProperty(name = "lasono.processing.worker-enabled", havingValue = "true", matchIfMissing = true)
class ProcessingWorker {

    private final RunNextProcessingJobUseCase runNextProcessingJob;

    ProcessingWorker(RunNextProcessingJobUseCase runNextProcessingJob) {
        this.runNextProcessingJob = runNextProcessingJob;
    }

    @Scheduled(fixedDelayString = "${lasono.processing.poll-interval-ms:2000}")
    void poll() {
        runNextProcessingJob.runAllDue();
    }
}
