package com.lasono.track.infrastructure.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.temporal.ChronoUnit;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import com.lasono.PostgresIntegrationTest;
import com.lasono.track.domain.Track;
import com.lasono.track.domain.TrackFixtures;
import com.lasono.track.domain.TrackId;

/**
 * The newest-first track list is paged by (created_at, id), so the column, its index and the
 * rule "created_at never changes" must hold on a real PostgreSQL, not only on H2.
 */
class TrackCreatedAtPostgresTest extends PostgresIntegrationTest {

    @Autowired
    private TrackPersistenceAdapter adapter;

    @Test
    void createdAtIsANotNullTimestampWithTimeZone() {
        Map<String, Object> column = jdbcTemplate.queryForMap(
            "SELECT data_type, is_nullable FROM information_schema.columns "
                + "WHERE table_name = 'tracks' AND column_name = 'created_at'");

        assertThat(column.get("data_type")).isEqualTo("timestamp with time zone");
        assertThat(column.get("is_nullable")).isEqualTo("NO");
    }

    @Test
    void anIndexOrdersTracksByCreatedAtThenIdNewestFirst() {
        String definition = jdbcTemplate.queryForObject(
            "SELECT indexdef FROM pg_indexes "
                + "WHERE tablename = 'tracks' AND indexname = 'idx_tracks_created_at_id'",
            String.class);

        assertThat(definition).contains("(created_at DESC, id DESC)");
    }

    @Test
    void savingATrackStoresWhenItWasCreated() {
        TrackId trackId = new TrackId(UUID.randomUUID());
        Instant before = Instant.now().truncatedTo(ChronoUnit.MICROS);

        adapter.save(new Track(trackId, TrackFixtures.OWNER, "Test Track", "Test description"));

        Instant after = Instant.now();
        assertThat(createdAt(trackId)).isBetween(before, after);
    }

    @Test
    void savingTheSameTrackAgainKeepsTheOriginalCreationTime() throws InterruptedException {
        TrackId trackId = new TrackId(UUID.randomUUID());
        Track track = new Track(trackId, TrackFixtures.OWNER, "Test Track", "Test description");
        adapter.save(track);
        Instant first = createdAt(trackId);

        Thread.sleep(20);
        adapter.save(track);

        assertThat(createdAt(trackId)).isEqualTo(first);
    }

    private Instant createdAt(TrackId trackId) {
        return jdbcTemplate
            .queryForObject("SELECT created_at FROM tracks WHERE id = ?", OffsetDateTime.class, trackId.getValue())
            .toInstant();
    }
}
