package com.lasono.track.application.usecase;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.io.ByteArrayInputStream;
import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;

import com.lasono.PostgresIntegrationTest;
import com.lasono.track.application.port.out.FailureOutcome;
import com.lasono.track.application.port.out.ProcessingJob;
import com.lasono.track.application.port.out.ProcessingJobQueue;
import com.lasono.track.domain.TrackId;
import com.lasono.track.infrastructure.persistence.ProcessingJobPersistenceAdapter;

/**
 * Uploading touches three tables (tracks, audio_resources, processing_jobs). They must change
 * together or not at all, which only a real database transaction can show.
 */
@Import(UploadTrackUseCasePostgresTest.FlakyQueueConfig.class)
class UploadTrackUseCasePostgresTest extends PostgresIntegrationTest {

    @Autowired
    private UploadTrackUseCase useCase;

    @Autowired
    private FlakyJobQueue queue;

    @AfterEach
    void makeTheQueueWorkAgain() {
        queue.enqueueFailure = null;
    }

    @Test
    void aFailedEnqueueRollsBackTheTrackAndItsAudioResource() {
        queue.enqueueFailure = new IllegalStateException("queue down");

        assertThrows(IllegalStateException.class, () -> useCase.execute(anUpload()));

        assertThat(count("tracks")).isZero();
        assertThat(count("audio_resources")).isZero();
    }

    private static UploadTrackCommand anUpload() {
        return new UploadTrackCommand(
            "My Song", "desc", new ByteArrayInputStream("data".getBytes()), 4L, "audio/mpeg");
    }

    private int count(String table) {
        return jdbcTemplate.queryForObject("SELECT count(*) FROM " + table, Integer.class);
    }

    /** The real queue, except that it can be told to fail when a job is added. */
    static class FlakyJobQueue implements ProcessingJobQueue {

        private final ProcessingJobQueue real;
        RuntimeException enqueueFailure;

        FlakyJobQueue(ProcessingJobQueue real) {
            this.real = real;
        }

        @Override
        public void enqueue(TrackId trackId) {
            if (enqueueFailure != null) {
                throw enqueueFailure;
            }
            real.enqueue(trackId);
        }

        @Override
        public Optional<ProcessingJob> claimNext(Duration lease) {
            return real.claimNext(lease);
        }

        @Override
        public void complete(UUID jobId) {
            real.complete(jobId);
        }

        @Override
        public FailureOutcome fail(UUID jobId, String error, Duration retryDelay) {
            return real.fail(jobId, error, retryDelay);
        }
    }

    @TestConfiguration
    static class FlakyQueueConfig {

        @Bean
        @Primary
        FlakyJobQueue flakyJobQueue(ProcessingJobPersistenceAdapter real) {
            return new FlakyJobQueue(real);
        }
    }
}
