package com.lasono.track.application.usecase;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
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
import com.lasono.track.domain.TrackId;
import com.lasono.track.domain.TrackSnapshot;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.model.TrackStatus;

class ProcessTrackUseCaseTest {

    private static final byte[] ORIGINAL = "original wav".getBytes(StandardCharsets.UTF_8);

    private InMemoryTrackRepository trackRepository;
    private InMemoryAudioStorage storage;
    private FakeAudioProcessor processor;
    private ProcessTrackUseCase useCase;

    @BeforeEach
    void setUp() {
        trackRepository = new InMemoryTrackRepository();
        storage = new InMemoryAudioStorage();
        processor = new FakeAudioProcessor();
        useCase = new ProcessTrackUseCase(trackRepository, storage, processor);
    }

    @Test
    void execute_shouldGiveTheOriginalAudioToTheProcessor() {
        TrackId id = anUploadedTrack();

        useCase.execute(id.getValue());

        assertEquals(1, processor.received.size());
        assertArrayEquals(ORIGINAL, processor.received.get(0));
    }

    @Test
    void execute_shouldMarkTheTrackReadyWithItsDurationAndWaveform() {
        TrackId id = anUploadedTrack();

        useCase.execute(id.getValue());

        Track track = trackRepository.findById(id).orElseThrow();
        TrackSnapshot snapshot = track.toSnapshot();
        assertEquals(TrackStatus.READY, track.getStatus());
        assertEquals(180_000L, snapshot.audioDuration().toMilliseconds());
        assertEquals(List.of(0.1f, 0.5f, 0.2f), snapshot.waveform().getSamples());
    }

    @Test
    void execute_shouldStoreTheConvertedMp3AndReferenceItFromTheTrack() {
        TrackId id = anUploadedTrack();

        useCase.execute(id.getValue());

        StreamingAudio streaming = trackRepository.findById(id).orElseThrow().toSnapshot().streamingAudio();
        assertEquals(AudioFormat.MP3, streaming.getFormat());
        assertEquals("audio/mpeg", streaming.getMimeType());
        assertEquals(FakeAudioProcessor.MP3_BYTES.length, streaming.getFileSize());
        assertArrayEquals(FakeAudioProcessor.MP3_BYTES, storage.files.get(streaming.getStorageKey()));
    }

    @Test
    void execute_shouldDoNothingWhenTheTrackIsAlreadyReady() {
        TrackId id = anUploadedTrack();
        useCase.execute(id.getValue());
        processor.received.clear();
        int storedFiles = storage.files.size();

        useCase.execute(id.getValue());

        assertTrue(processor.received.isEmpty(), "a finished track must not be processed again");
        assertEquals(storedFiles, storage.files.size());
        assertEquals(TrackStatus.READY, trackRepository.findById(id).orElseThrow().getStatus());
    }

    @Test
    void execute_shouldDoNothingWhenTheTrackHasFailed() {
        TrackId id = aFailedTrack();

        useCase.execute(id.getValue());

        assertTrue(processor.received.isEmpty(), "a failed track must not be processed again");
        assertEquals(TrackStatus.FAILED, trackRepository.findById(id).orElseThrow().getStatus());
    }

    private TrackId aFailedTrack() {
        TrackId id = anUploadedTrack();
        Track track = trackRepository.findById(id).orElseThrow();
        track.startProcessing();
        track.processingFailed();
        trackRepository.save(track);
        return id;
    }

    /** A track as it is right after the upload: the original file is stored and the track is PROCESSING. */
    private TrackId anUploadedTrack() {
        StorageKey key = storage.store(new ByteArrayInputStream(ORIGINAL), AudioFormat.WAV);
        Track track = new Track(new TrackId(UUID.randomUUID()), "My Song", "desc");
        track.uploadCompleted(new OriginalAudio(key.value(), AudioFormat.WAV, ORIGINAL.length, "audio/wav"));
        trackRepository.save(track);
        return track.getId();
    }
}
