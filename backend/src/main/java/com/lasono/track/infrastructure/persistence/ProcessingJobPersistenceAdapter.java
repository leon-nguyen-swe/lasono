package com.lasono.track.infrastructure.persistence;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Duration;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import com.lasono.track.application.port.out.FailureOutcome;
import com.lasono.track.application.port.out.ProcessingJob;
import com.lasono.track.application.port.out.ProcessingJobQueue;
import com.lasono.track.domain.TrackId;

@Repository
public class ProcessingJobPersistenceAdapter implements ProcessingJobQueue {

    // The database clock decides "now", so the app and the database cannot disagree about time.
    private static final String CLAIM_NEXT_SQL = """
        UPDATE processing_jobs
        SET status = 'RUNNING', attempts = attempts + 1, locked_until = now() + make_interval(secs => ?)
        WHERE id = (
            SELECT id FROM processing_jobs
            WHERE (status = 'PENDING' AND run_after <= now())
               OR (status = 'RUNNING' AND locked_until <= now() AND attempts < max_attempts)
            ORDER BY run_after
            LIMIT 1
            FOR UPDATE SKIP LOCKED)
        RETURNING id, track_id, attempts, max_attempts
        """;

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
        return jdbcTemplate.query(CLAIM_NEXT_SQL, ProcessingJobPersistenceAdapter::toJob, seconds(lease))
            .stream().findFirst();
    }

    @Override
    public void complete(ProcessingJob job) {
        jdbcTemplate.update(
            "UPDATE processing_jobs SET status = 'DONE', locked_until = NULL WHERE id = ?", job.id());
    }

    @Override
    public FailureOutcome fail(ProcessingJob job, String error, Duration retryDelay) {
        String newStatus = jdbcTemplate.queryForObject(
            """
            UPDATE processing_jobs
            SET status = CASE WHEN attempts < max_attempts THEN 'PENDING' ELSE 'FAILED' END,
                run_after = CASE WHEN attempts < max_attempts THEN now() + make_interval(secs => ?) ELSE run_after END,
                locked_until = NULL,
                last_error = ?
            WHERE id = ?
            RETURNING status
            """,
            String.class, seconds(retryDelay), error, job.id());
        return "PENDING".equals(newStatus) ? FailureOutcome.WILL_RETRY : FailureOutcome.GAVE_UP;
    }

    @Override
    public List<TrackId> failExhausted() {
        return jdbcTemplate.query(
            """
            UPDATE processing_jobs
            SET status = 'FAILED',
                locked_until = NULL,
                last_error = 'The lease expired and no attempts are left: the worker kept dying'
            WHERE status = 'RUNNING' AND locked_until <= now() AND attempts >= max_attempts
            RETURNING track_id
            """,
            (rs, rowNumber) -> new TrackId(rs.getObject("track_id", UUID.class)));
    }

    private static ProcessingJob toJob(ResultSet rs, int rowNumber) throws SQLException {
        return new ProcessingJob(
            rs.getObject("id", UUID.class),
            new TrackId(rs.getObject("track_id", UUID.class)),
            rs.getInt("attempts"),
            rs.getInt("max_attempts"));
    }

    private static double seconds(Duration duration) {
        return duration.toMillis() / 1000.0;
    }
}
