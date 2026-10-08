package com.lasono.track.application.usecase;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

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

class StreamTrackUseCaseTest {

    private static final byte[] ORIGINAL = "original wav".getBytes(StandardCharsets.UTF_8);
    private static final byte[] MP3 = "0123456789".getBytes(StandardCharsets.UTF_8);

    private InMemoryTrackRepository trackRepository;
    private InMemoryAudioStorage storage;
    private StreamTrackUseCase useCase;

    @BeforeEach
    void setUp() {
        trackRepository = new InMemoryTrackRepository();
        storage = new InMemoryAudioStorage();
        useCase = new StreamTrackUseCase(trackRepository, storage);
    }

    @Test
    void execute_shouldStreamTheConvertedMp3OfAReadyTrack() throws Exception {
        UUID id = aReadyTrack();

        StreamTrackResult result = useCase.execute(id, null);

        assertEquals("audio/mpeg", result.mimeType());
        assertEquals(MP3.length, result.fileSize());
        assertArrayEquals(MP3, result.stream().readAllBytes());
    }

    @Test
    void execute_shouldStreamOnlyTheRequestedRange() throws Exception {
        UUID id = aReadyTrack();

        StreamTrackResult result = useCase.execute(id, "bytes=2-5");

        assertTrue(result.partial());
        assertArrayEquals("2345".getBytes(StandardCharsets.UTF_8), result.stream().readAllBytes());
    }

    @Test
    void execute_shouldRefuseATrackThatIsStillProcessing() {
        UUID id = anUploadedTrack();

        assertThrows(TrackNotReadyException.class, () -> useCase.execute(id, null));
    }

    @Test
    void execute_shouldRefuseATrackWhoseProcessingFailed() {
        UUID id = anUploadedTrack();
        Track track = trackRepository.findById(new TrackId(id)).orElseThrow();
        track.startProcessing();
        track.processingFailed();
        trackRepository.save(track);

        assertThrows(TrackNotReadyException.class, () -> useCase.execute(id, null));
    }

    @Test
    void execute_shouldThrowWhenTheTrackDoesNotExist() {
        UUID missing = UUID.randomUUID();

        assertThrows(TrackNotFoundException.class, () -> useCase.execute(missing, null));
    }

    private UUID anUploadedTrack() {
        StorageKey key = storage.store(new ByteArrayInputStream(ORIGINAL), AudioFormat.WAV);
        Track track = new Track(new TrackId(UUID.randomUUID()), TrackFixtures.OWNER, "My Song", "desc");
        track.uploadCompleted(new OriginalAudio(key.value(), AudioFormat.WAV, ORIGINAL.length, "audio/wav"));
        trackRepository.save(track);
        return track.getId().getValue();
    }

    private UUID aReadyTrack() {
        UUID id = anUploadedTrack();
        Track track = trackRepository.findById(new TrackId(id)).orElseThrow();
        StorageKey mp3Key = storage.store(new ByteArrayInputStream(MP3), AudioFormat.MP3);
        track.startProcessing();
        track.processingCompleted(
            new StreamingAudio(mp3Key.value(), AudioFormat.MP3, MP3.length, "audio/mpeg"),
            new AudioDuration(3000L),
            new Waveform(List.of(0.1f, 0.5f)));
        trackRepository.save(track);
        return id;
    }
}
