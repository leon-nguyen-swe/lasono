package com.lasono.track.application.usecase;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.lasono.track.application.port.out.AudioProcessingException;
import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.domain.InMemoryTrackRepository;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.model.TrackStatus;

class RunNextProcessingJobUseCaseTest {

    private static final byte[] ORIGINAL = "original wav".getBytes(StandardCharsets.UTF_8);

    private InMemoryTrackRepository trackRepository;
    private InMemoryAudioStorage storage;
    private FakeAudioProcessor processor;
    private InMemoryProcessingJobQueue queue;
    private RunNextProcessingJobUseCase useCase;

    @BeforeEach
    void setUp() {
        trackRepository = new InMemoryTrackRepository();
        storage = new InMemoryAudioStorage();
        processor = new FakeAudioProcessor();
        queue = new InMemoryProcessingJobQueue();
        ProcessTrackUseCase processTrack = new ProcessTrackUseCase(trackRepository, storage, processor);
        useCase = new RunNextProcessingJobUseCase(queue, processTrack, trackRepository);
    }

    @Test
    void execute_shouldProcessTheTrackOfTheNextJobAndCompleteTheJob() {
        TrackId id = anUploadedTrackWithAJob();

        boolean tookAJob = useCase.execute();

        assertTrue(tookAJob);
        assertEquals(TrackStatus.READY, trackRepository.findById(id).orElseThrow().getStatus());
        assertEquals(InMemoryProcessingJobQueue.Status.DONE, queue.jobs.get(0).status);
    }

    @Test
    void execute_shouldDoNothingWhenNoJobIsDue() {
        boolean tookAJob = useCase.execute();

        assertFalse(tookAJob);
        assertTrue(processor.received.isEmpty());
    }

    @Test
    void execute_shouldReleaseTheJobForARetryWhenProcessingFailsAndAttemptsRemain() {
        TrackId id = anUploadedTrackWithAJob();
        processor.failure = new AudioProcessingException("corrupt audio");

        boolean tookAJob = useCase.execute();

        InMemoryProcessingJobQueue.Job job = queue.jobs.get(0);
        assertTrue(tookAJob);
        assertEquals(InMemoryProcessingJobQueue.Status.PENDING, job.status);
        assertTrue(job.lastError.contains("corrupt audio"), "the queue must know why it failed");
        assertEquals(TrackStatus.PROCESSING, trackRepository.findById(id).orElseThrow().getStatus());
    }

    @Test
    void execute_shouldWaitTwiceAsLongBeforeEachRetry() {
        anUploadedTrackWithAJob();
        processor.failure = new AudioProcessingException("corrupt audio");

        useCase.execute();
        assertEquals(Duration.ofSeconds(30), queue.jobs.get(0).lastRetryDelay);

        useCase.execute();
        assertEquals(Duration.ofSeconds(60), queue.jobs.get(0).lastRetryDelay);
    }

    @Test
    void execute_shouldMarkTheTrackFailedWhenTheJobRunsOutOfAttempts() {
        TrackId id = anUploadedTrackWithAJob();
        processor.failure = new AudioProcessingException("corrupt audio");

        for (int attempt = 1; attempt <= InMemoryProcessingJobQueue.MAX_ATTEMPTS; attempt++) {
            assertEquals(TrackStatus.PROCESSING, trackRepository.findById(id).orElseThrow().getStatus());
            useCase.execute();
        }

        assertEquals(InMemoryProcessingJobQueue.Status.FAILED, queue.jobs.get(0).status);
        assertEquals(TrackStatus.FAILED, trackRepository.findById(id).orElseThrow().getStatus());
    }

    @Test
    void execute_shouldGiveUpQuietlyOnAJobWhoseTrackDoesNotExist() {
        queue.enqueue(new TrackId(UUID.randomUUID()));

        for (int attempt = 1; attempt <= InMemoryProcessingJobQueue.MAX_ATTEMPTS; attempt++) {
            useCase.execute();
        }

        assertEquals(InMemoryProcessingJobQueue.Status.FAILED, queue.jobs.get(0).status);
    }

    @Test
    void execute_shouldLeaveAReadyTrackReadyWhenTheJobCannotBeReportedDone() {
        InMemoryProcessingJobQueue brokenQueue = new InMemoryProcessingJobQueue() {
            @Override
            public void complete(UUID jobId) {
                throw new IllegalStateException("db down");
            }
        };
        ProcessTrackUseCase processTrack = new ProcessTrackUseCase(trackRepository, storage, processor);
        RunNextProcessingJobUseCase brokenUseCase =
            new RunNextProcessingJobUseCase(brokenQueue, processTrack, trackRepository);
        TrackId id = anUploadedTrack();
        brokenQueue.enqueue(id);

        for (int attempt = 1; attempt <= InMemoryProcessingJobQueue.MAX_ATTEMPTS; attempt++) {
            brokenUseCase.execute();
        }

        assertEquals(InMemoryProcessingJobQueue.Status.FAILED, brokenQueue.jobs.get(0).status);
        assertEquals(TrackStatus.READY, trackRepository.findById(id).orElseThrow().getStatus());
    }

    @Test
    void runAllDue_shouldRunEveryDueJobAndCountThem() {
        TrackId first = anUploadedTrackWithAJob();
        TrackId second = anUploadedTrackWithAJob();
        TrackId third = anUploadedTrackWithAJob();

        int taken = useCase.runAllDue();

        assertEquals(3, taken);
        for (TrackId id : new TrackId[] {first, second, third}) {
            assertEquals(TrackStatus.READY, trackRepository.findById(id).orElseThrow().getStatus());
        }
    }

    @Test
    void runAllDue_shouldMarkTheTrackFailedWhenItsWorkerDiedOnEveryAttempt() {
        TrackId id = anUploadedTrackWithAJob();
        for (int attempt = 1; attempt <= InMemoryProcessingJobQueue.MAX_ATTEMPTS; attempt++) {
            queue.claimNext(Duration.ofMinutes(10)).orElseThrow();
            queue.expireLeases(); // the worker died: it never reported the job done or failed
        }

        int taken = useCase.runAllDue();

        assertEquals(0, taken, "nothing is left to run");
        assertEquals(InMemoryProcessingJobQueue.Status.FAILED, queue.jobs.get(0).status);
        assertEquals(TrackStatus.FAILED, trackRepository.findById(id).orElseThrow().getStatus());
    }

    @Test
    void runAllDue_shouldReturnZeroWhenNoJobIsDue() {
        assertEquals(0, useCase.runAllDue());
    }

    private TrackId anUploadedTrackWithAJob() {
        TrackId id = anUploadedTrack();
        queue.enqueue(id);
        return id;
    }

    /** A track as the upload leaves it: the original file is stored and the track is PROCESSING. */
    private TrackId anUploadedTrack() {
        StorageKey key = storage.store(new ByteArrayInputStream(ORIGINAL), AudioFormat.WAV);
        Track track = new Track(new TrackId(UUID.randomUUID()), "My Song", "desc");
        track.uploadCompleted(new OriginalAudio(key.value(), AudioFormat.WAV, ORIGINAL.length, "audio/wav"));
        trackRepository.save(track);
        return track.getId();
    }
}
