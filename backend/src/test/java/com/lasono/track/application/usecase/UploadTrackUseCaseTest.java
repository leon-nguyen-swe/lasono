package com.lasono.track.application.usecase;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.ByteArrayInputStream;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.lasono.track.application.port.out.AudioStorageException;
import com.lasono.track.domain.InMemoryTrackRepository;
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.audio.exception.AudioFormatInvalidException;
import com.lasono.track.domain.audio.exception.OriginalAudioInvalidException;
import com.lasono.track.domain.exception.TrackTitleInvalidException;

public class UploadTrackUseCaseTest {

    private UploadTrackUseCase useCase;
    private InMemoryTrackRepository trackRepository;

    @BeforeEach
    void setUp() {
        trackRepository = new InMemoryTrackRepository();
        useCase = new UploadTrackUseCase(new FakeAudioStorage(), trackRepository);
    }

    @Test
    void execute_shouldCreateTrackWithUploadedAudio() {
        UploadTrackCommand command = new UploadTrackCommand(
                "My Song", "desc",
                new ByteArrayInputStream("data".getBytes()),
                "song.mp3", 12345L, "audio/mpeg"
        );

        UploadTrackResult result = useCase.execute(command);

        assertNotNull(result);
        assertEquals("My Song", result.title());
        assertEquals("PROCESSING", result.status());
    }

    @Test
    void execute_shouldReturnValidTrackId() {
        UploadTrackCommand command = new UploadTrackCommand(
                "My Song", "desc",
                new ByteArrayInputStream("data".getBytes()),
                "song.mp3", 12345L, "audio/mpeg"
        );

        UploadTrackResult result = useCase.execute(command);

        assertNotNull(result.trackId());
        // trackId phải là UUID hợp lệ
        assertNotNull(java.util.UUID.fromString(result.trackId()));
    }

    @Test
    void execute_shouldPersistTrackToRepository() {
        UploadTrackCommand command = new UploadTrackCommand(
                "My Song", "desc",
                new ByteArrayInputStream("data".getBytes()),
                "song.mp3", 12345L, "audio/mpeg"
        );

        UploadTrackResult result = useCase.execute(command);

        TrackId trackId = new TrackId(java.util.UUID.fromString(result.trackId()));
        assertTrue(trackRepository.findById(trackId).isPresent());
    }

    @Test
    void execute_shouldStoreCorrectStorageKeyInTrack() {
        UploadTrackCommand command = new UploadTrackCommand(
                "My Song", "desc",
                new ByteArrayInputStream("data".getBytes()),
                "song.mp3", 12345L, "audio/mpeg"
        );

        UploadTrackResult result = useCase.execute(command);

        TrackId trackId = new TrackId(java.util.UUID.fromString(result.trackId()));
        String storageKey = trackRepository.findById(trackId)
                .orElseThrow()
                .toSnapshot()
                .originalAudio()
                .getStorageKey();
        // FakeAudioStorage tạo key theo pattern "fake/audio/<fileName>"
        assertEquals("fake/audio/song.mp3", storageKey);
    }

    @Test
    void execute_shouldSupportWavFormat() {
        UploadTrackCommand command = new UploadTrackCommand(
                "My Song", "desc",
                new ByteArrayInputStream("data".getBytes()),
                "song.wav", 12345L, "audio/wav"
        );

        UploadTrackResult result = useCase.execute(command);

        assertNotNull(result);
        assertEquals("PROCESSING", result.status());
    }

    @Test
    void execute_shouldThrowWhenTitleIsNull() {
        UploadTrackCommand command = new UploadTrackCommand(
                null, "desc",
                new ByteArrayInputStream("data".getBytes()),
                "song.mp3", 12345L, "audio/mpeg"
        );

        assertThrows(TrackTitleInvalidException.class, () -> useCase.execute(command));
    }

    @Test
    void execute_shouldThrowWhenTitleIsBlank() {
        UploadTrackCommand command = new UploadTrackCommand(
                "   ", "desc",
                new ByteArrayInputStream("data".getBytes()),
                "song.mp3", 12345L, "audio/mpeg"
        );

        assertThrows(TrackTitleInvalidException.class, () -> useCase.execute(command));
    }

    @Test
    void execute_shouldThrowWhenMimeTypeIsUnsupported() {
        UploadTrackCommand command = new UploadTrackCommand(
                "My Song", "desc",
                new ByteArrayInputStream("data".getBytes()),
                "song.ogg", 12345L, "audio/ogg"
        );

        assertThrows(AudioFormatInvalidException.class, () -> useCase.execute(command));
    }

    @Test
    void execute_shouldThrowWhenMimeTypeIsNull() {
        UploadTrackCommand command = new UploadTrackCommand(
                "My Song", "desc",
                new ByteArrayInputStream("data".getBytes()),
                "song.mp3", 12345L, null
        );

        assertThrows(AudioFormatInvalidException.class, () -> useCase.execute(command));
    }

    @Test
    void execute_shouldThrowWhenFileSizeIsZero() {
        UploadTrackCommand command = new UploadTrackCommand(
                "My Song", "desc",
                new ByteArrayInputStream("data".getBytes()),
                "song.mp3", 0L, "audio/mpeg"
        );

        assertThrows(OriginalAudioInvalidException.class, () -> useCase.execute(command));
    }

    @Test
    void execute_shouldThrowWhenFileSizeIsNegative() {
        UploadTrackCommand command = new UploadTrackCommand(
                "My Song", "desc",
                new ByteArrayInputStream("data".getBytes()),
                "song.mp3", -1L, "audio/mpeg"
        );

        assertThrows(OriginalAudioInvalidException.class, () -> useCase.execute(command));
    }

    @Test
    void execute_shouldPropagateAudioStorageException() {
        UploadTrackUseCase failingUseCase = new UploadTrackUseCase(new FailingAudioStorage(), trackRepository);
        UploadTrackCommand command = new UploadTrackCommand(
                "My Song", "desc",
                new ByteArrayInputStream("data".getBytes()),
                "song.mp3", 12345L, "audio/mpeg"
        );

        assertThrows(AudioStorageException.class, () -> failingUseCase.execute(command));
    }
}

