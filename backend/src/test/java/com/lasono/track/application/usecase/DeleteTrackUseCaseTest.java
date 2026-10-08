package com.lasono.track.application.usecase;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.ByteArrayInputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.transaction.support.TransactionOperations;

import com.lasono.track.application.port.out.AudioStorageException;
import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.domain.InMemoryTrackRepository;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackFixtures;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.audio.model.Waveform;
import com.lasono.track.domain.model.Visibility;

class DeleteTrackUseCaseTest {

    private static final UUID OWNER = TrackFixtures.OWNER.getValue();
    private static final UUID STRANGER = UUID.fromString("00000000-0000-0000-0000-0000000000b2");

    private InMemoryTrackRepository trackRepository;
    private InMemoryProcessingJobQueue jobQueue;
    private InMemoryAudioStorage storage;
    private DeleteTrackUseCase useCase;

    @BeforeEach
    void setUp() {
        trackRepository = new InMemoryTrackRepository();
        jobQueue = new InMemoryProcessingJobQueue();
        storage = new InMemoryAudioStorage();
        useCase = new DeleteTrackUseCase(
            trackRepository, jobQueue, storage, TransactionOperations.withoutTransaction());
    }

    /** An uploaded track with its original file stored and a job waiting for it. */
    private Track anUploadedTrack(Visibility visibility) {
        StorageKey original = storage.store(new ByteArrayInputStream("original".getBytes()), AudioFormat.WAV);
        Track track = new Track(new TrackId(UUID.randomUUID()), TrackFixtures.OWNER, "My Song", "desc", visibility);
        track.uploadCompleted(new OriginalAudio(original.value(), AudioFormat.WAV, 8, "audio/wav"));
        trackRepository.save(track);
        jobQueue.enqueue(track.getId());
        return track;
    }

    private Track aReadyTrack(Visibility visibility) {
        Track track = anUploadedTrack(visibility);
        StorageKey mp3 = storage.store(new ByteArrayInputStream("mp3".getBytes()), AudioFormat.MP3);
        track.startProcessing();
        track.processingCompleted(
            new StreamingAudio(mp3.value(), AudioFormat.MP3, 3, "audio/mpeg"),
            new AudioDuration(3000L),
            new Waveform(List.of(0.1f, 0.5f)));
        trackRepository.save(track);
        return track;
    }

    private boolean exists(Track track) {
        return trackRepository.findById(track.getId()).isPresent();
    }

    @Test
    void execute_shouldDeleteAReadyTrackWithBothItsFilesAndItsJobs() {
        Track track = aReadyTrack(Visibility.PUBLIC);
        assertEquals(2, storage.files.size());

        useCase.execute(track.getId().getValue(), OWNER);

        assertFalse(exists(track));
        assertTrue(storage.files.isEmpty(), "the original upload and the converted MP3 must both go");
        assertTrue(jobQueue.jobs.isEmpty());
    }

    @Test
    void execute_shouldDeleteAFailedTrackAndItsOriginalFile() {
        Track track = anUploadedTrack(Visibility.PRIVATE);
        track.startProcessing();
        track.processingFailed();
        trackRepository.save(track);

        useCase.execute(track.getId().getValue(), OWNER);

        assertFalse(exists(track));
        assertTrue(storage.files.isEmpty());
    }

    // The worker saves its result when it is done. If the track were gone by then, that save would bring it back.
    @Test
    void execute_shouldRefuseToDeleteATrackThatIsStillBeingProcessedAndChangeNothing() {
        Track track = anUploadedTrack(Visibility.PUBLIC);

        assertThrows(TrackStillProcessingException.class, () -> useCase.execute(track.getId().getValue(), OWNER));

        assertTrue(exists(track));
        assertEquals(1, storage.files.size());
        assertEquals(1, jobQueue.jobs.size());
    }

    @Test
    void execute_shouldRefuseAStrangerWhoCanSeeThePublicTrackAndDeleteNothing() {
        Track track = aReadyTrack(Visibility.PUBLIC);

        assertThrows(TrackNotOwnedException.class, () -> useCase.execute(track.getId().getValue(), STRANGER));

        assertTrue(exists(track));
        assertEquals(2, storage.files.size());
        assertEquals(1, jobQueue.jobs.size());
    }

    @Test
    void execute_shouldAnswerNotFoundForAStrangerAndAPrivateTrackAndDeleteNothing() {
        Track track = aReadyTrack(Visibility.PRIVATE);

        assertThrows(TrackNotFoundException.class, () -> useCase.execute(track.getId().getValue(), STRANGER));

        assertTrue(exists(track));
        assertEquals(2, storage.files.size());
    }

    @Test
    void execute_shouldAnswerNotFoundForATrackThatDoesNotExist() {
        assertThrows(TrackNotFoundException.class, () -> useCase.execute(UUID.randomUUID(), OWNER));
    }

    // If a file were deleted first and the database change then failed, a track would point at nothing.
    // The other way round, the worst case is a file nobody refers to.
    @Test
    void execute_shouldDeleteTheFilesOnlyAfterTheTrackIsGoneFromTheDatabase() {
        Track track = aReadyTrack(Visibility.PUBLIC);
        List<Boolean> trackWasGoneWhenAFileWasDeleted = new ArrayList<>();
        InMemoryAudioStorage watching = new InMemoryAudioStorage() {
            @Override
            public void delete(StorageKey key) {
                trackWasGoneWhenAFileWasDeleted.add(!exists(track));
                storage.delete(key);
            }
        };
        DeleteTrackUseCase watchingUseCase = new DeleteTrackUseCase(
            trackRepository, jobQueue, watching, TransactionOperations.withoutTransaction());

        watchingUseCase.execute(track.getId().getValue(), OWNER);

        assertEquals(List.of(true, true), trackWasGoneWhenAFileWasDeleted);
    }

    @Test
    void execute_shouldLeaveTheFilesAloneWhenTheDatabaseChangeFails() {
        Track track = aReadyTrack(Visibility.PUBLIC);
        InMemoryTrackRepository failing = new InMemoryTrackRepository() {
            @Override
            public void delete(TrackId id) {
                throw new IllegalStateException("db down");
            }
        };
        failing.save(track);
        DeleteTrackUseCase failingUseCase = new DeleteTrackUseCase(
            failing, jobQueue, storage, TransactionOperations.withoutTransaction());

        assertThrows(IllegalStateException.class, () -> failingUseCase.execute(track.getId().getValue(), OWNER));

        assertEquals(2, storage.files.size(), "the files must stay while the track is still there");
    }

    // The track is already gone from the database. A file that cannot be removed is a leftover, not a reason to
    // tell the owner that the delete failed.
    @Test
    void execute_shouldStillSucceedWhenAFileCannotBeRemoved() {
        Track track = aReadyTrack(Visibility.PUBLIC);
        InMemoryAudioStorage stuck = new InMemoryAudioStorage() {
            @Override
            public void delete(StorageKey key) {
                throw new AudioStorageException("disk error", new IllegalStateException());
            }
        };
        DeleteTrackUseCase stuckUseCase = new DeleteTrackUseCase(
            trackRepository, jobQueue, stuck, TransactionOperations.withoutTransaction());

        stuckUseCase.execute(track.getId().getValue(), OWNER);

        assertFalse(exists(track));
    }
}
