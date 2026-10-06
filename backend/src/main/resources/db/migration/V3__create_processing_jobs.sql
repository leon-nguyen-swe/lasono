-- Queue of audio processing jobs. A worker claims a job with FOR UPDATE SKIP LOCKED.
-- status: PENDING (waiting), RUNNING (claimed, see locked_until), DONE, FAILED (out of attempts).
CREATE TABLE processing_jobs
(
    id UUID NOT NULL,
    track_id UUID NOT NULL,
    status VARCHAR(50) NOT NULL,
    attempts INT NOT NULL DEFAULT 0,
    max_attempts INT NOT NULL DEFAULT 3,

    -- A PENDING job is not claimed before this time (used for the retry backoff).
    run_after TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- A RUNNING job whose lease passed this time is treated as abandoned by a dead worker.
    locked_until TIMESTAMPTZ,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_processing_jobs PRIMARY KEY (id),
    CONSTRAINT fk_processing_jobs_track FOREIGN KEY (track_id) REFERENCES tracks (id),
    CONSTRAINT uq_processing_jobs_track UNIQUE (track_id)
);

-- The claim query only looks at jobs that are still open, oldest due time first.
CREATE INDEX idx_processing_jobs_open ON processing_jobs (run_after)
    WHERE status IN ('PENDING', 'RUNNING');
