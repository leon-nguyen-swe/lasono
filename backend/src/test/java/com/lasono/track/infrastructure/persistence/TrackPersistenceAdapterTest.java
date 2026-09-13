package com.lasono.track.infrastructure.persistence;

import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackId;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;

import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest 
@Import(TrackPersistenceAdapter.class)
class TrackPersistenceAdapterTest {

    @Autowired
    private TrackPersistenceAdapter adapter;

    @Test
    void shouldSaveTrack() {
        TrackId trackId = new TrackId(UUID.randomUUID());
        Track track = new Track(
                trackId,
                "Test Track",
                "Test description"
        );

        adapter.save(track);

        Optional<Track> result = adapter.findById(trackId);

        assertThat(result).isPresent();
        assertThat(result.get().getId()).isEqualTo(trackId);
    }

    @Test
    void shouldFindTrackById() {
        TrackId trackId = new TrackId(UUID.randomUUID());
        Track track = new Track(
                trackId,
                "Test Track",
                "Test description"
        );

        adapter.save(track);

        Optional<Track> result = adapter.findById(trackId);

        assertThat(result).isPresent();
        assertThat(result.get().getId()).isEqualTo(trackId);
        assertThat(result.get().getTitle()).isEqualTo("Test Track");
        assertThat(result.get().getDescription()).isEqualTo("Test description");
    }

    @Test
    void shouldReturnEmptyWhenTrackDoesNotExist() {
        TrackId trackId = new TrackId(UUID.randomUUID());

        Optional<Track> result = adapter.findById(trackId);

        assertThat(result).isEmpty();
    }
}