package com.lasono.track.infrastructure.persistence;

import com.lasono.track.domain.OwnerId;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackFixtures;
import com.lasono.track.domain.TrackId;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import com.lasono.track.domain.model.Visibility;

@SpringBootTest 
@Import(TrackPersistenceAdapter.class)
class TrackPersistenceAdapterTest {

    @Autowired
    private TrackPersistenceAdapter adapter;

    @Autowired
    private TransactionTemplate transactionTemplate;

    @Test
    void shouldSaveTrack() {
        TrackId trackId = new TrackId(UUID.randomUUID());
        Track track = new Track(
                trackId,
                TrackFixtures.OWNER,
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
                TrackFixtures.OWNER,
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

    @Test
    void shouldKeepTheOwnerOfASavedTrack() {
        TrackId trackId = new TrackId(UUID.randomUUID());
        OwnerId owner = new OwnerId(UUID.randomUUID());
        adapter.save(new Track(trackId, owner, "Test Track", "Test description"));

        Optional<Track> result = adapter.findById(trackId);

        assertThat(result).isPresent();
        assertThat(result.get().getOwnerId()).isEqualTo(owner);
    }

    @Test
    void shouldKeepTheVisibilityOfASavedTrack() {
        TrackId privateId = new TrackId(UUID.randomUUID());
        TrackId publicId = new TrackId(UUID.randomUUID());
        adapter.save(new Track(privateId, TrackFixtures.OWNER, "Hidden", null, Visibility.PRIVATE));
        adapter.save(new Track(publicId, TrackFixtures.OWNER, "Shown", null));

        assertThat(adapter.findById(privateId).orElseThrow().getVisibility()).isEqualTo(Visibility.PRIVATE);
        assertThat(adapter.findById(publicId).orElseThrow().getVisibility()).isEqualTo(Visibility.PUBLIC);
    }

    @Test
    void shouldSaveTheChangesOfAnEditedTrack() {
        TrackId trackId = new TrackId(UUID.randomUUID());
        adapter.save(new Track(trackId, TrackFixtures.OWNER, "Old title", "old"));
        Track track = adapter.findById(trackId).orElseThrow();

        track.rename("New title");
        track.changeDescription("new");
        track.changeVisibility(Visibility.PRIVATE);
        adapter.save(track);

        Track reloaded = adapter.findById(trackId).orElseThrow();
        assertThat(reloaded.getTitle()).isEqualTo("New title");
        assertThat(reloaded.getDescription()).isEqualTo("new");
        assertThat(reloaded.getVisibility()).isEqualTo(Visibility.PRIVATE);
        assertThat(reloaded.getOwnerId()).isEqualTo(TrackFixtures.OWNER);
    }

    @Test
    void shouldFindATrackForUpdate() {
        TrackId trackId = new TrackId(UUID.randomUUID());
        adapter.save(new Track(trackId, TrackFixtures.OWNER, "Mine", null));

        // The lock lasts until the transaction ends, so there has to be one.
        transactionTemplate.executeWithoutResult(status -> {
            assertThat(adapter.findByIdForUpdate(trackId)).isPresent();
            assertThat(adapter.findByIdForUpdate(new TrackId(UUID.randomUUID()))).isEmpty();
        });
    }

    @Test
    void shouldDeleteATrackTogetherWithItsAudioResource() {
        TrackId trackId = new TrackId(UUID.randomUUID());
        adapter.save(new Track(trackId, TrackFixtures.OWNER, "Doomed", null));
        TrackId survivor = new TrackId(UUID.randomUUID());
        adapter.save(new Track(survivor, TrackFixtures.OWNER, "Survivor", null));

        adapter.delete(trackId);

        assertThat(adapter.findById(trackId)).isEmpty();
        assertThat(adapter.findById(survivor)).isPresent();
    }

    @Test
    void shouldAcceptDeletingATrackThatIsNotThere() {
        adapter.delete(new TrackId(UUID.randomUUID()));
    }
}
