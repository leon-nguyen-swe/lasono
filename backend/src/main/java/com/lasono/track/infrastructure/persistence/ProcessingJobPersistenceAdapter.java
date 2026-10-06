package com.lasono.track.infrastructure.persistence;

import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import com.lasono.track.application.port.out.ProcessingJobQueue;
import com.lasono.track.domain.TrackId;

@Repository
public class ProcessingJobPersistenceAdapter implements ProcessingJobQueue {

    private final JdbcTemplate jdbcTemplate;

    public ProcessingJobPersistenceAdapter(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @Override
    public void enqueue(TrackId trackId) {
        jdbcTemplate.update(
            "INSERT INTO processing_jobs (id, track_id, status) VALUES (?, ?, 'PENDING')",
            UUID.randomUUID(), trackId.getValue());
    }
}
