-- Who can see a track. Every track that exists today was public, so the existing rows become PUBLIC.
ALTER TABLE tracks
    ADD COLUMN visibility VARCHAR(20) NOT NULL DEFAULT 'PUBLIC';

-- No default from now on: the code must say it. A forgotten value would otherwise decide who can see a track.
ALTER TABLE tracks
    ALTER COLUMN visibility DROP DEFAULT;

-- The code parses the value, but a direct INSERT must not be able to store anything else.
ALTER TABLE tracks
    ADD CONSTRAINT ck_tracks_visibility CHECK (visibility IN ('PUBLIC', 'PRIVATE'));
