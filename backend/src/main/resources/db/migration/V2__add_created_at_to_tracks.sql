ALTER TABLE tracks
    ADD COLUMN created_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Keyset pagination of the newest-first track list: ORDER BY created_at DESC, id DESC.
CREATE INDEX idx_tracks_created_at_id ON tracks (created_at DESC, id DESC);
