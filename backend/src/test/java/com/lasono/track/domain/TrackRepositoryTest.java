package com.lasono.track.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import com.lasono.track.domain.audio.model.AudioDuration;
import com.lasono.track.domain.audio.model.AudioFormat;
import com.lasono.track.domain.audio.model.OriginalAudio;
import com.lasono.track.domain.audio.model.StreamingAudio;
import com.lasono.track.domain.audio.model.Waveform;

class TrackRepositoryTest {

    private TrackRepository repository;

    @BeforeEach
    void setUp() {
        repository = new InMemoryTrackRepository();
    }

    // --- Helpers ---

    private Track createTrack(TrackId id, String title) {
        return new Track(id, title, null);
    }

    private Track createTrack(String title) {
        return createTrack(new TrackId(UUID.randomUUID()), title);
    }

    private Track makeReady(Track track) {
        track.uploadCompleted(new OriginalAudio(
            "original/audio.wav",
            AudioFormat.WAV,
            10_000L,
            "audio/wav"
        ));
        track.startProcessing();
        track.processingCompleted(
            new StreamingAudio("streaming/audio.mp3", AudioFormat.MP3, 8_000L, "audio/mpeg"),
            new AudioDuration(180_000L),
            new Waveform(java.util.List.of(0.1f, 0.5f, 0.8f))
        );
        return track;
    }

    // --- save ---

    @Test
    void shouldReturnSavedTrack() {
        Track track = createTrack("My Track");

        Track saved = repository.save(track);

        assertNotNull(saved);
        assertSame(track, saved);
    }

    @Test
    void shouldPersistTrackAfterSave() {
        TrackId id = new TrackId(UUID.randomUUID());
        Track track = createTrack(id, "My Track");

        repository.save(track);
        Optional<Track> found = repository.findById(id);

        assertTrue(found.isPresent());
    }

    @Test
    void shouldOverwriteTrackOnSaveWithSameId() {
        TrackId id = new TrackId(UUID.randomUUID());
        Track original = createTrack(id, "Original Title");
        repository.save(original);

        Track updated = makeReady(createTrack(id, "Updated Title"));
        repository.save(updated);

        Optional<Track> found = repository.findById(id);
        assertTrue(found.isPresent());
        assertEquals("Updated Title", found.get().getTitle());
    }

    // --- findById ---

    @Test
    void shouldReturnEmptyForUnknownId() {
        TrackId unknownId = new TrackId(UUID.randomUUID());

        Optional<Track> result = repository.findById(unknownId);

        assertTrue(result.isEmpty());
    }

    @Test
    void shouldFindSavedTrackById() {
        TrackId id = new TrackId(UUID.randomUUID());
        Track track = createTrack(id, "My Track");
        repository.save(track);

        Optional<Track> found = repository.findById(id);

        assertTrue(found.isPresent());
        assertEquals(id, found.get().getId());
        assertEquals("My Track", found.get().getTitle());
    }

    @Test
    void shouldFindTrackPreservingStatus() {
        Track track = createTrack("Ready Track");
        makeReady(track);
        repository.save(track);

        Optional<Track> found = repository.findById(track.getId());

        assertTrue(found.isPresent());
        assertEquals(
            com.lasono.track.domain.model.TrackStatus.READY,
            found.get().getStatus()
        );
    }

    @Test
    void shouldStoreDifferentTracksIndependently() {
        Track first = createTrack("First Track");
        Track second = createTrack("Second Track");
        repository.save(first);
        repository.save(second);

        Optional<Track> foundFirst = repository.findById(first.getId());
        Optional<Track> foundSecond = repository.findById(second.getId());

        assertTrue(foundFirst.isPresent());
        assertTrue(foundSecond.isPresent());
        assertEquals("First Track", foundFirst.get().getTitle());
        assertEquals("Second Track", foundSecond.get().getTitle());
    }

    @Test
    void shouldNotReturnOtherTrackForDifferentId() {
        Track track = createTrack("My Track");
        repository.save(track);

        TrackId otherId = new TrackId(UUID.randomUUID());
        Optional<Track> result = repository.findById(otherId);

        assertTrue(result.isEmpty());
    }

}
