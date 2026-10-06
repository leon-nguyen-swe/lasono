package com.lasono.track.infrastructure.persistence;

import java.time.Duration;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import com.lasono.track.application.port.out.ProcessingJob;
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

    @Override
    public Optional<ProcessingJob> claimNext(Duration lease) {
        // The database clock decides "now", so the app and the database cannot disagree about time.
        return jdbcTemplate.query(
                """
                UPDATE processing_jobs
                SET status = 'RUNNING', attempts = attempts + 1, locked_until = now() + make_interval(secs => ?)
                WHERE id = (
                    SELECT id FROM processing_jobs
                    WHERE status = 'PENDING' AND run_after <= now()
                    ORDER BY run_after
                    LIMIT 1)
                RETURNING id, track_id, attempts, max_attempts
                """,
                (rs, rowNumber) -> new ProcessingJob(
                    rs.getObject("id", UUID.class),
                    new TrackId(rs.getObject("track_id", UUID.class)),
                    rs.getInt("attempts"),
                    rs.getInt("max_attempts")),
                lease.toMillis() / 1000.0)
            .stream().findFirst();
    }
}
