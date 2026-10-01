CREATE TABLE tracks
(
    id UUID NOT NULL,
    title VARCHAR(255) NOT NULL,
    description VARCHAR(255),
    status VARCHAR(50) NOT NULL,

    CONSTRAINT pk_tracks PRIMARY KEY (id)
);

CREATE TABLE audio_resources
(
    id UUID NOT NULL,
    track_id UUID NOT NULL,
    status VARCHAR(50) NOT NULL,

    original_storage_key VARCHAR(512),
    original_format VARCHAR(50),
    original_file_size BIGINT,
    original_mime_type VARCHAR(100),

    streaming_storage_key VARCHAR(512),
    streaming_format VARCHAR(50),
    streaming_file_size BIGINT,
    streaming_mime_type VARCHAR(100),

    duration_ms BIGINT,
    waveform_samples REAL[],

    CONSTRAINT pk_audio_resources PRIMARY KEY (id),
    CONSTRAINT fk_audio_resources_track FOREIGN KEY (track_id) REFERENCES tracks (id),
    CONSTRAINT uq_audio_resources_track UNIQUE (track_id)
);
