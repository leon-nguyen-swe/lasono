package com.lasono.track.application.usecase;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.lasono.track.application.port.out.AudioStorage;
import com.lasono.track.application.port.out.AudioStorageException;
import com.lasono.track.application.port.out.StorageKey;
import com.lasono.track.domain.InMemoryTrackRepository;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackRepository;
import com.lasono.track.domain.audio.exception.AudioFormatInvalidException;
import com.lasono.track.domain.audio.exception.OriginalAudioInvalidException;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.exception.TrackTitleInvalidException;

public class UploadTrackUseCaseTest {

    private UploadTrackUseCase useCase;
    private InMemoryTrackRepository trackRepository;
    private InMemoryProcessingJobQueue jobQueue;

    @BeforeEach
    void setUp() {
        trackRepository = new InMemoryTrackRepository();
        jobQueue = new InMemoryProcessingJobQueue();
        useCase = new UploadTrackUseCase(new FakeAudioStorage(), trackRepository, jobQueue);
    }

    @Test
    void execute_shouldCreateTrackWithUploadedAudio() {
        UploadTrackCommand command = anUpload();

        UploadTrackResult result = useCase.execute(command);

        assertNotNull(result);
        assertEquals("My Song", result.title());
        assertEquals("PROCESSING", result.status());
    }

    @Test
    void execute_shouldReturnValidTrackId() {
        UploadTrackCommand command = anUpload();

        UploadTrackResult result = useCase.execute(command);

        assertNotNull(result.trackId());
        // trackId phải là UUID hợp lệ
        assertNotNull(java.util.UUID.fromString(result.trackId()));
    }

    @Test
    void execute_shouldPersistTrackToRepository() {
        UploadTrackCommand command = anUpload();

        UploadTrackResult result = useCase.execute(command);

        TrackId trackId = new TrackId(java.util.UUID.fromString(result.trackId()));
        assertTrue(trackRepository.findById(trackId).isPresent());
    }

    @Test
    void execute_shouldEnqueueAProcessingJobForTheNewTrack() {
        UploadTrackCommand command = anUpload();

        UploadTrackResult result = useCase.execute(command);

        TrackId trackId = new TrackId(java.util.UUID.fromString(result.trackId()));
        assertEquals(List.of(trackId), jobQueue.enqueued);
    }

    @Test
    void execute_shouldStoreCorrectStorageKeyInTrack() {
        UploadTrackCommand command = anUpload();

        UploadTrackResult result = useCase.execute(command);

        TrackId trackId = new TrackId(java.util.UUID.fromString(result.trackId()));
        String storageKey = trackRepository.findById(trackId)
                .orElseThrow()
                .toSnapshot()
                .originalAudio()
                .getStorageKey();
        // FakeAudioStorage tạo key theo pattern "fake/audio/<extension>"
        assertEquals("fake/audio/mp3", storageKey);
    }

    @Test
    void execute_shouldSupportWavFormat() {
        UploadTrackCommand command = anUpload("My Song", 12345L, "audio/wav");

        UploadTrackResult result = useCase.execute(command);

        assertNotNull(result);
        assertEquals("PROCESSING", result.status());
    }

    @Test
    void execute_shouldThrowWhenTitleIsNull() {
        UploadTrackCommand command = anUpload(null, 12345L, "audio/mpeg");

        assertThrows(TrackTitleInvalidException.class, () -> useCase.execute(command));
    }

    @Test
    void execute_shouldThrowWhenTitleIsBlank() {
        UploadTrackCommand command = anUpload("   ", 12345L, "audio/mpeg");

        assertThrows(TrackTitleInvalidException.class, () -> useCase.execute(command));
    }

    @Test
    void execute_shouldThrowWhenMimeTypeIsUnsupported() {
        UploadTrackCommand command = anUpload("My Song", 12345L, "audio/ogg");

        assertThrows(AudioFormatInvalidException.class, () -> useCase.execute(command));
    }

    @Test
    void execute_shouldThrowWhenMimeTypeIsNull() {
        UploadTrackCommand command = anUpload("My Song", 12345L, null);

        assertThrows(AudioFormatInvalidException.class, () -> useCase.execute(command));
    }

    @Test
    void execute_shouldThrowWhenFileSizeIsZero() {
        UploadTrackCommand command = anUpload("My Song", 0L, "audio/mpeg");

        assertThrows(OriginalAudioInvalidException.class, () -> useCase.execute(command));
    }

    @Test
    void execute_shouldThrowWhenFileSizeIsNegative() {
        UploadTrackCommand command = anUpload("My Song", -1L, "audio/mpeg");

        assertThrows(OriginalAudioInvalidException.class, () -> useCase.execute(command));
    }

    @Test
    void execute_shouldPropagateAudioStorageException() {
        UploadTrackUseCase failingUseCase = new UploadTrackUseCase(new FailingAudioStorage(), trackRepository, jobQueue);
        UploadTrackCommand command = anUpload();

        assertThrows(AudioStorageException.class, () -> failingUseCase.execute(command));
    }

    // -----------------------------------------------------------------------
    // Stored file lifecycle: a rejected upload must not leave a file behind
    // -----------------------------------------------------------------------

    @Test
    void execute_shouldNotStoreFileWhenTitleIsBlank() {
        RecordingAudioStorage storage = new RecordingAudioStorage();
        UploadTrackUseCase recordingUseCase = new UploadTrackUseCase(storage, trackRepository, jobQueue);
        UploadTrackCommand command = anUpload("   ", 12345L, "audio/mpeg");

        assertThrows(TrackTitleInvalidException.class, () -> recordingUseCase.execute(command));

        assertTrue(storage.stored.isEmpty(), "no file must be written for an invalid title");
    }

    @Test
    void execute_shouldDeleteStoredFileWhenFileSizeIsZero() {
        RecordingAudioStorage storage = new RecordingAudioStorage();
        UploadTrackUseCase recordingUseCase = new UploadTrackUseCase(storage, trackRepository, jobQueue);
        UploadTrackCommand command = anUpload("My Song", 0L, "audio/mpeg");

        assertThrows(OriginalAudioInvalidException.class, () -> recordingUseCase.execute(command));

        assertEquals(storage.stored, storage.deleted, "the stored file must be deleted again");
    }

    @Test
    void execute_shouldDeleteStoredFileAndRethrowWhenSaveFails() {
        RecordingAudioStorage storage = new RecordingAudioStorage();
        RuntimeException saveFailure = new IllegalStateException("db down");
        TrackRepository failingRepository = new TrackRepository() {
            @Override
            public Track save(Track track) {
                throw saveFailure;
            }

            @Override
            public Optional<Track> findById(TrackId id) {
                return Optional.empty();
            }
        };
        UploadTrackUseCase recordingUseCase = new UploadTrackUseCase(storage, failingRepository, jobQueue);
        UploadTrackCommand command = anUpload();

        RuntimeException thrown = assertThrows(RuntimeException.class, () -> recordingUseCase.execute(command));

        assertSame(saveFailure, thrown);
        assertEquals(1, storage.stored.size());
        assertEquals(storage.stored, storage.deleted);
    }

    @Test
    void execute_shouldDeleteStoredFileAndRethrowWhenEnqueueFails() {
        RecordingAudioStorage storage = new RecordingAudioStorage();
        RuntimeException enqueueFailure = new IllegalStateException("queue down");
        jobQueue.enqueueFailure = enqueueFailure;
        UploadTrackUseCase recordingUseCase = new UploadTrackUseCase(storage, trackRepository, jobQueue);
        UploadTrackCommand command = anUpload();

        RuntimeException thrown = assertThrows(RuntimeException.class, () -> recordingUseCase.execute(command));

        assertSame(enqueueFailure, thrown);
        assertEquals(1, storage.stored.size());
        assertEquals(storage.stored, storage.deleted);
    }

    @Test
    void execute_shouldKeepOriginalExceptionWhenCleanupDeleteFails() {
        RecordingAudioStorage storage = new RecordingAudioStorage();
        storage.failOnDelete = true;
        UploadTrackUseCase recordingUseCase = new UploadTrackUseCase(storage, trackRepository, jobQueue);
        UploadTrackCommand command = anUpload("My Song", 0L, "audio/mpeg");

        OriginalAudioInvalidException thrown = assertThrows(
            OriginalAudioInvalidException.class, () -> recordingUseCase.execute(command)
        );

        assertEquals(1, thrown.getSuppressed().length, "cleanup failure must be attached, not thrown");
    }

    @Test
    void execute_shouldKeepStoredFileOnSuccess() {
        RecordingAudioStorage storage = new RecordingAudioStorage();
        UploadTrackUseCase recordingUseCase = new UploadTrackUseCase(storage, trackRepository, jobQueue);
        UploadTrackCommand command = anUpload();

        recordingUseCase.execute(command);

        assertEquals(1, storage.stored.size());
        assertTrue(storage.deleted.isEmpty());
    }

    private static UploadTrackCommand anUpload() {
        return anUpload("My Song", 12345L, "audio/mpeg");
    }

    private static UploadTrackCommand anUpload(String title, long fileSize, String mimeType) {
        return new UploadTrackCommand(
                title, "desc",
                new ByteArrayInputStream("data".getBytes()),
                fileSize, mimeType
        );
    }

    private static final class RecordingAudioStorage implements AudioStorage {

        final List<StorageKey> stored = new ArrayList<>();
        final List<StorageKey> deleted = new ArrayList<>();
        boolean failOnDelete;

        @Override
        public StorageKey store(InputStream audioData, AudioFormat audioFormat) {
            StorageKey key = new StorageKey("recorded-" + stored.size() + "." + audioFormat.getExtension());
            stored.add(key);
            return key;
        }

        @Override
        public InputStream retrieve(StorageKey key) {
            return new ByteArrayInputStream(new byte[0]);
        }

        @Override
        public InputStream retrieveRange(StorageKey key, long offset, long length) {
            return new ByteArrayInputStream(new byte[0]);
        }

        @Override
        public void delete(StorageKey key) {
            if (failOnDelete) {
                throw new AudioStorageException("cannot delete", new RuntimeException("io"));
            }
            deleted.add(key);
        }
    }
}

