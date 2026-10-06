package com.lasono.track.infrastructure.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import com.lasono.PostgresIntegrationTest;
import com.lasono.track.domain.TrackId;

/**
 * The job queue relies on PostgreSQL features (row locks with SKIP LOCKED, UPDATE ... RETURNING), so
 * it is tested on a real database, not on H2.
 */
class ProcessingJobPersistenceAdapterPostgresTest extends PostgresIntegrationTest {

    @Autowired
    private ProcessingJobPersistenceAdapter adapter;

    @Test
    void enqueueStoresAPendingJobForTheTrack() {
        UUID trackId = insertTrack();

        adapter.enqueue(new TrackId(trackId));

        List<Map<String, Object>> jobs = jdbcTemplate.queryForList(
            "SELECT track_id, status, attempts FROM processing_jobs");
        assertThat(jobs).hasSize(1);
        assertThat(jobs.get(0)).containsEntry("track_id", trackId);
        assertThat(jobs.get(0)).containsEntry("status", "PENDING");
        assertThat(jobs.get(0)).containsEntry("attempts", 0);
    }

    private UUID insertTrack() {
        UUID id = UUID.randomUUID();
        jdbcTemplate.update(
            "INSERT INTO tracks (id, title, description, status) VALUES (?, 'a song', NULL, 'PROCESSING')", id);
        return id;
    }
}
